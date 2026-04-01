# x-install

用于一键安装与管理 xray-core 的脚本工具，支持交互式菜单、自动生成配置字段、更新内核与 GEO 数据。

---

## 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/zjjscwt/x-install/main/x-install.sh -o /root/x-install.sh && chmod +x /root/x-install.sh && /root/x-install.sh
```

执行后将自动创建快捷命令：`daili`，后续可直接在终端输入 `daili` 进入管理菜单。

---

## 功能说明

- 安装 / 更新内核 / 更新 GEO 数据
- 启动 / 停止 / 重启 / 状态查看
- 卸载并清理所有文件（含 daili、脚本与模板）

---

## 配置模板来源

安装时会自动从仓库获取配置模板：

```
https://raw.githubusercontent.com/zjjscwt/x-install/main/config-example.json
```

---

## 注意事项

- 需在支持 systemd 的 Linux 系统上运行
- 需使用 root 权限执行
- 卸载会删除脚本本体与模板文件（确认输入 y）


