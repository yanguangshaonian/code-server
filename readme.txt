code-server 自用维护分支

维护分支: byok/server-owned
官方基线: v4.143.1, 22ddf60dbc52f164cff13620ab515086dd08c90a
VS Code: 1.143.1, e646868227c3e3a9e3f24277c8c7220be42c0be7
PR: https://github.com/coder/code-server/pull/8047
固定来源: 73f71d62f4b26c04dd50b595a3837231a1b5b6aa

本分支直接从官方基线创建, 不继承此前自定义分支的提交.
保留官方 VS Code gitlink, 自定义代码由 patches/series 中末尾三个补丁承载:
- copilot-background-byok.diff: 服务器内存持有 BYOK direct provider 配置.
- copilot-agenthost-session-changes.diff: PR 自带的 Changes 选择修正.
- server-web-build.diff: 允许 core-ci 仅生成 server-web bundle.
保留 PR 对 Copilot harness 默认值的调整. 不包含 Sessions Web.

原 PR 面向 VS Code 1.141. 本次仅处理 1.143.1 的版本冲突:
导入位置和接口上下文, dispatchAction 的 credentials 参数及 Promise 返回类型,
BYOK 设置默认值和 Ambient 同步作用域, workingSet 优先于 worktree 默认值,
以及对应测试适配. 恢复插入 contribution 时覆盖的官方说明注释.
移植复用了此前已验证的冲突解决结果, 未引入额外执行器或运行时兼容层.

执行边界:
Copilot SDK 通过服务器直连可转换的 BYOK 模型. Local 执行路径未改写.
凭据同步消息在 AHP JSONL 日志中脱敏, 快照只保存在 Agent Host 内存.
浏览器断连后快照仍在, Agent Host 重启后需客户端重新同步.
thinking: true, 特殊请求头等无法直接表达的配置仍会被 direct 转换排除.
远程链路没有完整 renderer 推理回退, 此类模型可能不会显示.
推理强度和模型质量不等价, 不能通过删除 thinking 字段保证效果不变.
真实 BYOK 在全部浏览器关闭后的多轮任务持续执行仍需端到端验证.

首次准备与构建:
统一入口: bash ci/build/build-isolated.sh
先提交主仓库修改, 脚本只构建当前 HEAD. 使用符合子模块 .nvmrc 的 Node,
并安装 git, npm, quilt, jq, rsync, nfpm, envsubst, timeout 等工具及官方原生编译依赖.
每次在 /tmp/vscode/build-<commit>-<随机后缀>/ 下建立独立源码和依赖,
日志位于 logs/, 安装包位于 source/release-packages/, 校验值为 SHA256SUMS.
中间文件, npm 缓存和临时文件也放在该目录, 不向原项目写入构建产物.
脚本不安装系统包, 不部署服务, 不复用已有工作区的 node_modules.
网络代理和原生编译工具按宿主机环境准备. 失败时保留目录及分阶段日志.
当前宿主机默认 Node 已升级为 24.22.1, npm 为 11.19.1.
Electron 43.7.7 头文件不能由此机 GCC 11 正确编译; 已验证宿主机
clang-20/clang++-20 配合 GCC 11 标准库可正常编译链接. 本机使用:
export CC=clang-20 CXX=clang++-20
export CXXFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/11
export LDFLAGS=--gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/11
export VSCODE_REMOTE_CC=gcc VSCODE_REMOTE_CXX=g++
export VSCODE_REMOTE_CXXFLAGS='' VSCODE_REMOTE_LDFLAGS=''
这些是本机工具链设置, 不是通用路径, 不应硬编码到依赖源码.
代理通过 HTTP_PROXY/HTTPS_PROXY 和 NODE_USE_ENV_PROXY=1 传入,
同时设置 NO_PROXY=localhost,127.0.0.1. 如 GitHub API 代理出口返回 403,
应先验证直连, 确认可用后再将 api.github.com 加入 NO_PROXY.
该入口固定 VSCODE_BUILD_TARGET=server-web 和 VSCODE_TARGET=linux-x64,
仅构建 Linux x86_64 的 server-web bundle, 不构建 desktop 或纯 server bundle.
保留官方必要的扩展编译, 核心类型检查和源码转译, 最终生成 server-web release,
并检查发布 product.json 与前端 bundle 的 commit/quality 一致性.
2026-10-29 已完成提交 4c02260 的完整源码发布构建.
首次入口在依赖安装中遇到工具链及网络问题; 使用上述宿主机编译参数和
代理环境后, 在同一隔离目录重试依赖, 继续执行脚本的剩余步骤并成功.
不是一次无干预构建; 未更改依赖源码, 未跳过编译与类型检查.
该次产物在目标筛选改动之前生成, 当时 core-ci 仍编译了三个 bundle 目标.
后续统一入口已限定 server-web; 已验证任务选择与补丁重放.
提交 944a496 已通过统一入口完成一次无中途重试的完整构建,
使用上述 Clang 和代理环境. 日志确认 bundle 目标只有 server-web.
构建目录: /tmp/vscode/build-944a496-Iq0O2v
deb: /tmp/vscode/build-944a496-Iq0O2v/source/release-packages/code-server_4.143.1-byok-944a496_amd64.deb
大小约 223 MiB, 架构 amd64. 三种产物 SHA256 校验通过.
最终 deb 解包启动后, 编辑器, 前端 bundle 和远端 Seti 主题均返回 200,
前后端 commit/quality 一致, 无页面异常. 记录位于 logs/runtime-check.json.
构建目录: /tmp/vscode/build-4c02260-lsK7EA
deb: /tmp/vscode/build-4c02260-lsK7EA/source/release-packages/code-server_4.143.1-byok-4c02260_amd64.deb
大小约 223 MiB. 另有 rpm, tar.gz 和 SHA256SUMS, 三种产物校验均通过.
Debian 内部版本为 4.143.1~byok-4c02260, 排序低于官方正式版 4.143.1.
最终 deb 解包启动验证: 编辑器 HTTP 200, 前端 bundle HTTP 200,
远端 Seti 图标主题资源 HTTP 200, 前后端 commit/quality 一致, 无页面异常.
验证记录位于 logs/runtime-check.json. 未安装或重启生产服务,
真实 BYOK 与全部浏览器关闭后的持续执行未在本次发布包上验证.

按照 docs/CONTRIBUTING.md 安装项目要求的 Node 和依赖.
git submodule update --init --recursive
quilt push -a --fuzz=0
安装依赖后使用官方 build, build:vscode, release, package 脚本.
例如 VERSION=4.143.1 npm run build:vscode, 其余环境按 ci/build 脚本准备.
不能跳过构建时的 quality=stable 和 BUILD_SOURCEVERSION 准备.
发布必须使用同一次构建的配套前后端与依赖, 不用官方 deb 底座覆盖独立 bundle.
验证前后端 commit/quality 一致, 主题 JSON, 扩展字体与图标资源返回 200.
旧 tag 对应的 148 MiB 混合 deb 已知存在资源路径故障, 不应继续使用.
旧二进制文件不代表本分支的新构建产物.

跟随官方升级:
1. 确认工作区无未保存修改, 保存当前可工作的提交并新建升级分支.
2. quilt pop -a, 将 VS Code 工作目录恢复至当前官方 gitlink 对应源码.
3. git fetch origin --tags, 将目标官方 release tag merge 到升级分支.
4. 保留目标官方版本的 lib/vscode gitlink, git submodule update --init.
5. quilt push -a --fuzz=0, 逐个处理失败补丁. 必要时 quilt push -f 后,
   依据目标版本接口修复拒绝块, 删除 .rej, quilt refresh, 再应用下一补丁.
6. 优先使用新官方实现, 已由官方实现的补丁应删除, 不保留重复兼容路径.
7. 检查定向类型与测试, pop/push 零 fuzz 重放全部补丁, 再完整构建发布包.
8. 验证 BYOK 注册, 凭据日志脱敏, 真实请求, 主题字体与浏览器断连重连.
9. 将升级合入 byok/server-owned 并为验证通过的源码打新 tag.

核心回归入口:
node lib/vscode/build/next/index.ts build-fast --client-only
node lib/vscode/test/unit/node/index.js --runGlob '**/platform/agentHost/test/{node/byokLmBridgeRegistry,node/copilotSessionLauncher,node/protocolServerHandler,common/ahpJsonlLogger}.test.js'
浏览器测试覆盖 AgentHostByokLmHandler 和 AgentHostSessionInputPills.
跨模块接口调整后运行 npm --prefix lib/vscode run typecheck-client.

2026-10-29 本次移植验证:
- build-fast --client-only 重新生成测试产物成功.
- 客户端 typecheck-client 通过, 580 项定向 Node 测试通过.
- 99 项 Chromium 测试通过. 官方测试 fixture 缺少 code-server 要求的
    userDataPath, 测试时仅临时修改生成 JS 补齐目录, 验证后已撤销.
- 全部 31 个补丁 pop/push 零 fuzz 重放通过, 官方子模块 gitlink 未改动.
- 本次未重新生成发布包, 未部署或重启生产服务.

2026-10-29 仓库恢复后的 Copilot 上下文修复:
- remote-chat-attachments.diff: 普通和待发送消息的资源附件转换为当前远端真实 URI,
    保留其他主机地址, 附件元数据和未保存内容快照.
- copilot-editor-context.diff: 传递当前源文件路径, 为未保存内容保留源文件身份;
    首次提交按手选目录, 活动文件所属项目, 文件树目录和默认目录选择工作目录.
    自动推荐不冒充手选, 正式会话固定初始目录, 销毁时清理锁定状态.
- 客户端 typecheck-client 通过, build-fast --client-only 通过,
    三个相关测试文件的 764 项 Chromium 测试通过.
- 两个补丁已完成零 fuzz 撤销重放. 本轮未生成新发布包,
    未部署或重启 Cloud Studio, 真实模型端到端行为尚待验证.

旧自定义 tag 保留用于追溯. 旧 cleanup/byok-background 开发分支删除,
后续开发以 byok/server-owned 为准. 不因本次源码重建自动部署生产服务.