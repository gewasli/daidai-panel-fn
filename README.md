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
# 输出：dist/daidai-panel-fn-1.0.0.fpk
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
trim-cli file upload /vol1/appcenter-downloads/upload ./dist/daidai-panel-fn-1.0.0.fpk --overwrite replace --yes
trim-cli app install-fpk --remote-path /vol1/appcenter-downloads/upload/daidai-panel-fn-1.0.0.fpk --volume-id 1 --yes
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
