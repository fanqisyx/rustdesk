# 公司远控管理：设计与当前改造范围

产品目标是让公司掌握「谁能看到、连接哪台设备，以何种方式连接」，并能清晰区分内部资产和外部客户资产。

当前首发范围：单公司、客户端自行注册与登录、管理员也可创建员工账号、内部固定资产与外部客户设备分组、按员工授权分组、自建 Linux/Docker 管理服务。首版不接企业微信、LDAP 或 AD。用户于 2026-10-25 将原先的管理员建号模式调整为允许客户端自助注册。

实现与运行说明见 [management/README.md](../management/README.md)。

## 领域与决策

- **账号**是操作员身份；设备服务凭据独立于账号。账号登录不自动成为资产归属。
- **自助注册**创建启用的普通成员账号，并立即返回登录会话；不赋予管理员身份、分组权限或设备归属。管理员继续负责设备入库与授权，可通过环境变量关闭新注册。
- **设备**是公司纳管的被控计算机，使用真实 RustDesk ID，唯一归属一个分组。
- **分组**是内部资产或外部客户的树形结构。同一父组下名称唯一；完整路径用于兼容现有客户端按名称筛选的界面。
- **授权**赋予员工某一分组及其后代的操作集合，可设置截止时间。默认拒绝，允许取并集；没有隐式归属授权或显式拒绝优先级。
- **设备分享**将已纳管单台电脑的部分权限分配给另一个账号。分享者须有管理员直接授予的 `share` 和对应操作权限；接收者不能通过分享链继续扩大权限。目录和连接授权同时读取当前分享及上游权限，不靠客户端隐藏按钮执行安全策略。
- **连接票据**是账号管理平面和 RustDesk 数据平面的衔接。短期、单次、绑定连接 challenge，目标机在线核验。目录过滤不替代连接授权。
- **本机同意**仍由 RustDesk 的设备密码、人工确认和本机策略提供。集中授权与本机同意同时满足才能连接。

首版采用独立 Python/FastAPI + SQLite 服务，原因是无需将音视频及平台依赖引入管理服务，部署和权限测试可以独立完成。schema v2 新增设备分享表，支持 v1 原位升级，不支持横向多实例；数据量增大后再迁移 PostgreSQL，不预先构建抽象存储层。

保留 hbbs/hbbr，不修改共享 hbb_common 子模块；新增的票据字段位于本仓库自己的 libs/base 协议。缺少该字段的旧控制端会被受管目标明确拒绝。

## 现有运行路径的变更面

| 现有文件 | 必要行为变化 |
| --- | --- |
| flutter/lib/common/widgets/login.dart | 以自建公司账号登录／注册对话框替换旧账号、OIDC、邮件验证码界面；增加确认密码及注册模式切换，保留其他页面使用的登录和退出入口 |
| flutter/lib/models/user_model.dart | 公司登录及注册成功后检查服务标识，保存服务地址／令牌；注册返回 201，原有公司登录仍接受 200；退出清除管理员状态 |
| flutter/lib/utils/http_service.dart | 已配置公司服务的请求使用严格证书校验和禁止重定向，避免公司令牌进入旧的证书错误回退路径 |
| flutter/lib/models/group_model.dart | 公司目录不读取离线缓存，读取失败清空可见设备，避免错误保留授权目录 |
| flutter/lib/common/hbbs/hbbs.dart | 读取服务端可选的 can_share 字段；旧服务器没有此字段时为 false |
| flutter/lib/common/widgets/peer_card.dart | 仅对公司目录中可转授的设备增加分享菜单；其他菜单内容保持原路径 |
| flutter/lib/common/widgets/peers_view.dart | 公司设备目录选择父分组时，同时显示已获授权的子组设备；其他目录筛选规则不变 |
| flutter/lib/models/ab_model.dart | 公司账号不从本地通讯录缓存恢复设备目录，避免离线恢复过期授权信息 |
| libs/base/protos/message.proto | LoginRequest 增加字段 18，携带单次票据，不发送账号会话令牌给被控机 |
| libs/base/src/config/keys.rs | 增加公司服务器及设备凭据两个配置键 |
| src/lib.rs | 注册独立 enterprise 模块 |
| src/client.rs | 原生客户端发送登录请求前获取绑定当前 challenge 和会话类型的票据；未配置公司服务且非受管时沿用原登录内容 |
| src/ui_session_interface.rs | 公司账号会话令牌不传给 hbbs/hbbr，保持管理服务与原有穿透中继服务的凭据独立 |
| src/server/connection.rs | 受管端在密码或人工确认前核验票据，失败即关闭；受管端拒绝交换控制方向；非受管分支保持原行为 |
| src/lang/*.rs | 为新增登录提示加入翻译键，简体中文提供翻译，其余缺省使用英文 |
| .github/workflows/flutter-build.yml | 为公司发布增加可选的编译期强制纳管及服务器地址输入；未传公司参数的既有构建保持原默认值 |
| README.md、.gitignore | 根说明增加公司版部署、分享与验证边界；忽略本机生成的公司发布附件 |

自助注册此次还变更 management/app.py（公开注册、普通成员限制和限流）、management/models.py（注册字段与确认密码校验）、management/static/index.html 与 app.js（网页注册入口）、management/compose.yaml（注册开关），以及专用于公司请求的 enterprise_http.dart（注册请求）。无需修改数据库 schema、设备授权规则或 Rust 远控路径。

设备分享增加独立的 company_device_sharing.dart 请求模块和 company_device_sharing_dialog.dart 窗口，GroupModel 在已有拉取／清空／退出流程中维护可分享设备 ID，不修改通用 Peer 结构或 FFI。管理服务新增 v2 分享表、share 分组权限、分享管理接口，以及按设备合并权限的函数；目录、票据签发和被控端核验必须同时使用它，以保证收到分享的用户可见且可连接、撤权时真正拒绝连接。设备移组／停用会删除分享。网页增加分享窗口和列表，测试增加授权边界、连接时重新核验及 v1 数据保留。此次无需改变 Rust 远控协议。

其他操作系统捕获、输入、编码、穿透、中继和非受管端的密码校验未改动。新业务实现集中在 management/ 与 src/enterprise.rs。详细限制（已有会话不会被即时切断、Web 远控、Sciter、权限粒度）必须按运行说明告知部署人员。
