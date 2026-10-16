# daidai-panel-fn

飞牛 fnOS 上的「呆呆面板」原生应用（`.fpk` 包）。

把 **呆呆面板**以 **独立 Docker 项目**的方式打包进 fnOS 应用中心：

- 容器名、端口、数据目录全部独立，**内部更新/升级不影响你原有的面板**；
- 面板本体由 `linzixuanzz/daidai-panel` 镜像提供，本包只负责安装、托管、数据目录；
- 容器**以 root 运行**——这是刻意的：Linux 系统依赖（`apt-get` / `apk`）必须 root，
  且 npm/pip 需要可写的 `HOME`，非 root 时连 `npm ls` 都会失败。

## 目录结构

```text
daidai-panel-fn/
├── manifest                    # 应用清单（appname 必须稳定）
├── config/
│   ├── privilege               # run-as: root
│   └── resource                # docker-project + data-share 声明
├── app/
│   ├── docker/
│   │   └── docker-compose.yaml # 容器定义（端口 / 数据卷 / 环境变量）
│   └── ui/
│       ├── config              # 桌面入口（type=url, port 5700）
│       └── images/             # icon_64.png / icon_256.png
├── cmd/
│   ├── main                    # start / stop / status
│   └── *_init, *_callback      # 安装 / 升级 / 卸载 / 配置 钩子
├── wizard/                     # 安装向导（可为空）
├── ICON.PNG / ICON_256.PNG     # 应用图标
└── build.sh                    # 打 .fpk
```

## 构建

```bash
./build.sh
# 输出：dist/daidai-panel-fn-1.0.1.fpk
```

`build.sh` 优先调用官方 `fnpack build`；若环境里没有 `fnpack`（例如 GitHub
Actions 的干净 runner），自动回退到内置的纯 Python 打包器，产物格式完全一致。

### ⚠️ 关于 `.fpk` 格式

`.fpk` 必须是 **gzip 压缩的 tar**，**不是 zip**。早先版本用 `zipfile` 打包，
应用中心解析不了，`app install-fpk` 会直接报：

```
app-center request POST /app-center/v1/download/upload failed: ({"code":10111,"msg":""})
```

包内结构：

```text
daidai-panel-fn.fpk   (gzip tar)
├── manifest
├── ICON.PNG / ICON_256.PNG
├── cmd/              (main + 各 *_init / *_callback)
├── config/           (privilege, resource)
├── wizard/
└── app.tgz           (gzip tar；内容 = app/ + config/，即安装后的 target/)
```

## 安装

```bash
# 把包放到 fnOS 能读到的位置，然后：
trim-cli file upload /vol1/appcenter-downloads/upload ./dist/daidai-panel-fn-1.0.1.fpk --overwrite replace --yes
trim-cli app install-fpk --remote-path /vol1/appcenter-downloads/upload/daidai-panel-fn-1.0.1.fpk --volume-id 1 --yes
```

也可以在 **应用中心 → 手动安装** 里直接选 `.fpk`。

安装后访问 `http://<宿主机IP>:5700`。

## 数据

数据落在 fnOS 的 data-share：

```text
/var/apps/daidai-panel-fn/shares/daidai-panel-fn/data   （→ /vol1/@appshare/daidai-panel-fn/data）
```

挂载进容器为 `/app/Dumb-Panel`，里面有 `daidai.db`、`.jwt_secret`、`deps/`、
`logs/`、`scripts/` 等。**升级只替换应用目录，不会碰这个 share**，所以 SQLite、
依赖、脚本、登录态全部保留。

> 该目录属主是 root 且权限为 `700`。用普通用户直接 `cp` 会被拒绝；
> 需要写入时用 Docker 以 root 操作，例如：
>
> ```bash
> docker run --rm -v /vol1/@appshare/daidai-panel-fn/data:/dest -v /tmp:/backup alpine \
>   sh -c 'tar xzf /backup/daidai-backup.tar.gz -C /dest --strip-components=1'
> ```

## 从旧面板迁移数据

1. 停掉旧容器，打包旧数据目录（形如 `/vol2/1000/daidai/Dumb-Panel`）；
2. 安装本应用，等它首次启动完成（会生成一份全新的空库）；
3. 停掉本应用，用上面的 `docker run` 方式把备份解包覆盖进 data 目录；
4. 启动本应用。

`PANEL_UPDATE_MANAGER=disabled` 已关闭面板自带的 watchtower 自更新，避免它去动别的容器。

---

## ⚠️ 为什么用 Debian 镜像，而不是默认的 Alpine

本应用固定使用 **`linzixuanzz/daidai-panel:3.3.6-debian`**（Debian 12 bookworm / glibc），
而不是默认的 `latest`（Alpine / musl）。原因见官方文档「关于 Playwright / 浏览器自动化脚本」：

| 问题 | Alpine（musl） | Debian（glibc） |
| --- | --- | --- |
| Playwright 官方 Chromium | 是 glibc 构建，**根本执行不了** | 正常运行 |
| Python `playwright` 包 | 只发 manylinux，**连装都装不上** | 正常安装 |
| 面板「一键安装 Playwright 运行环境」 | 按钮置灰 | 支持 |
| Chromium / chromedriver | `apk add` 常因索引与触发器问题失败 | `apt-get install` 稳定成功 |

### 「装成功了，不久又失败」的真正原因

面板的 Linux 系统依赖装在**容器内**，而容器重建（升级应用、改 compose、`docker rm` 重建）
会把容器层丢掉。官方文档写明：**26 个系统库随旧容器一起丢，但已登记成 Linux 依赖，
面板启动校验会在后台自动重装。**

所以在 Alpine 版镜像上会陷入死循环：

```text
装成功 → 容器重建 → 系统库丢 → 启动校验自动重装 → apk 装不上 → 状态 failed
       → 下次重启再试 → 再失败 …
```

根因是面板源码 `server/service/linux_packages.go` 里 **apk 分支从不刷新索引**：

```go
case "apk":
    return manager.Binary, []string{"add", "--no-cache", packageName}, nil   // 没有 apk update
case "apt":
    script := "export DEBIAN_FRONTEND=noninteractive; "
    if refreshApt { script += "apt-get update; " }                            // apt 会刷新
    script += "apt-get install -y --no-install-recommends " + ...
```

Alpine 的 `v3.23` 是滚动仓库，镜像烘焙的索引很快过期；`apk add --no-cache` 拿着过期索引
去拉已下架的版本号，于是逐包 `HTTP 404` / `I/O error`，最后 `gtk+3.0` 触发器
以 127 退出，面板判为 `failed`。apt 分支自带 `apt-get update`，所以 Debian 上不会出现这个问题。

### 迁移后需要处理的三件事（本应用已内置）

1. **镜像换成 Debian** —— compose 里 `image:` 与 `IMAGE_NAME` 都是 `:3.3.6-debian`。
2. **`/dev/shm` 加到 1GB** —— compose 里 `shm_size: 1gb`。默认 64MB 会让 Chromium 崩溃。
3. **依赖名改成 Debian 包名** —— 面板不做到发行版名映射，`dependencies` 表里存的是
   你输入的原名。Alpine 名到 Debian 名的对应：

   | 面板里常见写法（Alpine） | Debian 包名 |
   | --- | --- |
   | `chromium` | `chromium` |
   | `chromium-chromedriver` | `chromium-driver` |
   | `build-base` | `build-essential` |
   | `linux-headers` | `linux-libc-dev` |
   | `cmake` | `cmake` |
   | `dotnet8-sdk` | 无 Debian 包（需 Microsoft 源）；bili 脚本会自行装 .NET 10 |

4. **Alpine→Debian 后 Python 原生扩展要重装** —— 面板 v3.3.3+ 会自动检出
   `deps/python/<版本>/.daidai-python-libc` 与当前镜像的 C 库不一致，并在后台按原版本重装。
   日志形如：

   ```text
   [Python 依赖] Python 3.12 环境里有 5 个包按另一种 C 库编译，在当前镜像（glibc）上加载不了：
   cffi==2.1.1、charset_normalizer==3.5.1、curl_cffi==0.16.3、lxml==6.1.3、psutil==7.2.2，后台按原版本重装
   ```

### 验证过的行为（本机实测）

```bash
# 1. 容器重建后系统包确实会丢
docker rm -f daidai-panel-fn && docker compose up -d
# → chromium / chromium-driver / build-essential / linux-libc-dev / cmake 全部 MISSING

# 2. 面板启动校验自动重装（约 2 分钟）
docker logs daidai-panel-fn | grep 'dep verify'
# [INFO] dep verify: linux/chromium missing after restart, scheduled automatic reinstall
# [INFO] dep verify: scheduled 5 missing dependencies for automatic reinstall after restart

# 3. 重装成功
docker exec daidai-panel-fn sh -c 'for p in chromium chromium-driver build-essential linux-libc-dev cmake; do
  printf "%-20s " $p; dpkg-query -W -f="${Status}\n" $p 2>/dev/null || echo MISSING; done'
# 全部 install ok installed
```

### 如果还要跑 Playwright

按官方文档：**依赖管理 → Linux → 安装 Playwright 运行环境**（26 个系统包 + Python `playwright`
+ 浏览器下载到 `deps/ms-playwright`）。浏览器与 Python 包都在数据卷里，重建不丢；
26 个系统库会在重建后由启动校验自动重装。
