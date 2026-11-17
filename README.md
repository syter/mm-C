# mm-C 武器轮抽乱斗

Godot 4.7 · GDScript

## 跑起来
```bash
godot --path .                                    # 正常打开
godot --path . -- --host --bots=3                 # 开主机 + 3 个机器人，直接进轮抽
godot --path . -- --join=127.0.0.1 --name=小明    # 再开一个窗口加入
```

## 测试
```bash
godot --headless --path . --script res://tests/regression/test_core.gd
```
截图（模式选择 + 分队战斗，不能加 --headless）：
```bash
godot --path . --script res://tests/tools/capture_mode.gd -- /tmp
```
联机冒烟测试（两个进程，全机器人操作，打完一局退出；`--mode=K` 强制模式，0 = 各自为战）：
```bash
godot --headless --path . -- --host --wait=2 --autoplay --quit-after=1 &
godot --headless --path . -- --join=127.0.0.1 --autoplay --quit-after=1
```

## 结构
- `scripts/core/` 武器表、战斗模拟（纯逻辑，无头可测）
- `scripts/net/net.gd` 联机 + 对局状态机（autoload `Net`）
- `scripts/ai/bot.gd` 机器人
- `scripts/ui/` 画面、界面、音效播放
- `tools/gen_sfx.py` 合成音效（`python3 tools/gen_sfx.py`）

设计和待定项见 `DESIGN.md`。
