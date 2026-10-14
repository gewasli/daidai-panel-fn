# daidai-panel-fn <!-- omit in toc -->

飞牛 fnOS 上的「呆呆面板」原生应用（.fnOS .fpk 包）。

本项目把 **呆呆面板**以 **独立 Docker 项目**方式打包，运行在 fnOS 应用中心：
- 与你**现有的 daidai 面板隔离**（容器名、暴露端口、数据卷全部独立），内部更新/升级不会影响主面板。
- 面板本体通过 `linzixuanzz/daidai-panel` 镜像提供（Docker 项目，不由本包内嵌）。
- 必须以 **root** 运行（Docker 项目推荐 root），否则「Linux 系统依赖」不能安装，npm/pip 的 HOME 也不一定可写。

## 目录结构

```text
daidai-panel-fn/
├── manifest                 # fnOS 应用清单（appname 必须稳定）
├── config/
│   ├── privilege            # 最小权限：包用户运行（不用 root 长期跑服务）
│   └── resource             # 声明 docker-project（app/docker 目录）
├── app/
│   ├── docker/
│   │   └── docker-compose.yaml   # 独立 daidai 容器：按 PANEL_PORT 映射，数据在 ./data
│   └── ui/
│       └── config             # 桌面入口（type=url，host 端口 5701）
│           └── images/
│               ├── icon_64.png
│               └── icon_256.png
├── cmd/
│   └── main                 # start/stop/status 生命周期（TRIM_APPDEST 驱动）
├── wizard/                  # 安装/升级/配置向导（按需补充）
├── ICON.PNG / ICON_256.PNG  # 应用图标（64/256）
├── icon_gen.py              # 生成图标（纯标准库，不需要 PIL）
└── build.sh                 # 打 .fpk
```

## 构建

```bash
# 1) 生成图标（可选；本项目用生成的占位图）
python3 icon_gen.py .

# 2) 打包
./build.sh
# 输出：dist/daidai-panel-fn-1.0.0.fpk
```

## 在 fnOS 上安装

1. 把 `daidai-panel-fn-*.fpk` 拖到 **应用中心 → 应用管理 → 导入**，或用
   `appcenter-cli install-fpk daidai-panel-fn-1.0.0.fpk`。
2. 安装完成后，在应用中心看到「呆呆面板」入口，打开地址是
   `http://宿主机IP:5701`。
3. 如要自动升级：把本 `dist/*.fpk` 放进你自己的 **fndepot 自定义源**，fnOS 会按源更新。

## 升级 / 数据如何保证不丢失

- 数据全在 `app/docker/data`（挂载到容器 `/app/Dumb-Panel`），外置卷；
- 升级只替换容器镜像，不动 `data`，所以 SQLite、依赖、脚本、登录态都保留。
- 若要彻底重装：`docker compose down` 后再 `up -d`，或删除旧 fpk 并安装新版本；
  只会丢容器，但数据卷保持。

## 当前已知假定

- `appname=daidai-panel-fn` 需保持稳定；如要改名，必须同时改 `manifest`、`cmd/main` 里的
  `desktop_applaunchname`、`config/resource`、`cmd/main` 里所有 `daidai-panel-fn` 字符串。
- 图标是按「D」形状的占位图；如你有官方 logo，请替换 `ICON.PNG` / `ICON_256.PNG`
 （规格：64×64 / 256×256，sRGB，单文件 ≤ 1024 KB）。
