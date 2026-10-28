use base::{
    config::keys,
    message_proto::{login_request, LoginRequest, Message},
};
use hbb_common::{
    bail,
    config::{Config, LocalConfig},
    ResultType,
};
use serde_json::{json, Value};
use std::time::Duration;

fn pinned_server() -> String {
    option_env!("RUSTDESK_ENTERPRISE_SERVER")
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| Config::get_option(keys::OPTION_ENTERPRISE_SERVER))
}

pub fn is_managed() -> bool {
    option_env!("RUSTDESK_ENTERPRISE_REQUIRED") == Some("1")
        || !pinned_server().is_empty()
        || !Config::get_option(keys::OPTION_ENTERPRISE_DEVICE_TOKEN).is_empty()
}

pub fn transport_token(token: String) -> String {
    // Company sessions belong to the management API, never to hbbs/hbbr.
    if token.starts_with("rd_session_") {
        String::new()
    } else {
        token
    }
}

fn api_url(server: &str, path: &str) -> ResultType<String> {
    api_url_with_http_origin(
        server,
        path,
        &Config::get_option(keys::OPTION_ENTERPRISE_HTTP_ORIGIN),
        &LocalConfig::get_option(keys::OPTION_ENTERPRISE_HTTP_ORIGIN),
    )
}

fn api_url_with_http_origin(
    server: &str,
    path: &str,
    device_http_origin: &str,
    account_http_origin: &str,
) -> ResultType<String> {
    let parsed = url::Url::parse(server)?;
    let loopback = matches!(parsed.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"));
    let origin = parsed.origin().ascii_serialization();
    let allow_http = loopback || origin == device_http_origin || origin == account_http_origin;
    if !(parsed.scheme() == "https" || parsed.scheme() == "http" && allow_http)
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
        || parsed.path() != "/"
    {
        bail!("Use HTTPS or explicitly enable plaintext HTTP for this server");
    }
    Ok(format!("{}{path}", server.trim_end_matches('/')))
}

pub fn action(lr: &LoginRequest) -> &'static str {
    match lr.union.as_ref() {
        Some(login_request::Union::FileTransfer(_)) => "file_transfer",
        Some(login_request::Union::Terminal(_)) => "terminal",
        Some(login_request::Union::PortForward(_)) => "tunnel",
        Some(login_request::Union::ViewCamera(_)) => "camera",
        _ => "connect",
    }
}

async fn post(server: &str, path: &str, token: &str, body: Value) -> ResultType<Value> {
    if token.is_empty() {
        bail!("Company login or device credential is required");
    }
    let url = api_url(server, path)?;
    // Credentials must never follow redirects or the legacy invalid-certificate fallback.
    let response = reqwest::Client::builder()
        .timeout(Duration::from_secs(8))
        .redirect(reqwest::redirect::Policy::none())
        .build()?
        .post(url)
        .bearer_auth(token)
        .json(&body)
        .send()
        .await?;
    if !response.status().is_success() {
        bail!(
            "Company access denied (HTTP {})",
            response.status().as_u16()
        );
    }
    Ok(response.json().await?)
}

pub async fn attach_ticket(message: &mut Message, challenge: &str) -> ResultType<()> {
    let server = LocalConfig::get_option(keys::OPTION_ENTERPRISE_SERVER);
    let server = if server.is_empty() {
        pinned_server()
    } else {
        server
    };
    if server.is_empty() && !is_managed() {
        return Ok(());
    }
    let lr = message.mut_login_request();
    let response = post(
        &server,
        "/api/enterprise/tickets",
        &LocalConfig::get_option("access_token"),
        json!({
            "device_id": lr.username,
            "controller_id": lr.my_id,
            "action": action(lr),
            "challenge": challenge,
        }),
    )
    .await?;
    let Some(ticket) = response
        .get("ticket")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
    else {
        bail!("Invalid company authorization response");
    };
    lr.enterprise_ticket = ticket.to_owned();
    Ok(())
}

pub async fn verify_login(lr: &LoginRequest, challenge: &str) -> ResultType<()> {
    if !is_managed() {
        return Ok(());
    }
    if lr.enterprise_ticket.is_empty() {
        bail!("Company login is required; use the company RustDesk client");
    }
    let response = post(
        &pinned_server(),
        "/api/enterprise/verify",
        &Config::get_option(keys::OPTION_ENTERPRISE_DEVICE_TOKEN),
        json!({
            "ticket": lr.enterprise_ticket,
            "device_id": Config::get_id(),
            "controller_id": lr.my_id,
            "action": action(lr),
            "challenge": challenge,
        }),
    )
    .await?;
    if response.get("allowed").and_then(Value::as_bool) != Some(true) {
        bail!("Company access denied");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn company_sessions_are_not_rendezvous_credentials() {
        assert!(transport_token("rd_session_private".to_owned()).is_empty());
        assert_eq!(transport_token("legacy-token".to_owned()), "legacy-token");
    }

    #[test]
    fn company_credentials_require_a_trusted_origin() {
        assert!(api_url("https://management.example.com", "/api/enterprise/verify").is_ok());
        assert!(api_url("http://127.0.0.1:21114", "/api/enterprise/verify").is_ok());
        for value in [
            "http://example.com",
            "https://user:pass@example.com",
            "https://example.com/api",
            "https://example.com?token=secret",
        ] {
            assert!(api_url(value, "/api/enterprise/verify").is_err());
        }
    }

    #[test]
    fn plaintext_http_approval_is_bound_to_the_server_and_port() {
        let server = "http://203.0.113.10:21114";
        let path = "/api/enterprise/verify";
        assert!(api_url_with_http_origin(server, path, "", "").is_err());
        assert!(api_url_with_http_origin(server, path, server, "").is_ok());
        assert!(api_url_with_http_origin(server, path, "", server).is_ok());
        for value in [
            "http://203.0.113.10:24443",
            "http://203.0.113.11:21114",
            "http://user:password@203.0.113.10:21114",
            "http://203.0.113.10:21114/api",
        ] {
            assert!(api_url_with_http_origin(value, path, server, server).is_err());
        }
    }

    #[test]
    fn each_session_type_requests_its_own_permission() {
        let mut lr = LoginRequest::new();
        assert_eq!(action(&lr), "connect");
        lr.set_file_transfer(Default::default());
        assert_eq!(action(&lr), "file_transfer");
        lr.set_terminal(Default::default());
        assert_eq!(action(&lr), "terminal");
        lr.set_port_forward(Default::default());
        assert_eq!(action(&lr), "tunnel");
        lr.set_view_camera(Default::default());
        assert_eq!(action(&lr), "camera");
    }
}
