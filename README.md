# Rhythm 4K

Godot 4.7.2 制作的 4K 下落式音游。

## 功能

- 4 条轨道，梯形透视
- Tap / Hold 音符，Hold 支持按住或上滑
- 判定：PERFECT / GREAT / GOOD / MISS
- 分数、连击、准度、S/A/B/C 评级
- 暂停面板：速度 0-28、轨道宽度 0.4-1.0
- 设置持久化到 `user://settings.cfg`
- Android 导出

## 环境

- Godot 4.7.2
- Android 导出模板（打 APK 时需要）

## 运行

1. 克隆仓库
2. 在 `new-my_type/<歌曲文件夹>/` 放入你自己的 `audio.ogg`
   （仓库不包含音频文件）
3. 用 Godot 4.7.2 打开 `project.godot`
4. 按 F5 运行

## 目录

```
game.gd             主游戏逻辑（判定、渲染、对象池）
note.gd             单个音符（圆盘 + 尾巴贴图）
game_config.gd      全局配置 + 绝对/相对路径 + 设置持久化
menu_controller.gd  登录 -> 选曲 -> 选难度
diff_card.gd        难度卡片
diagonal_bg.gd      菜单斜线背景
Main.tscn           入口场景
Game.tscn           游戏场景
Note.tscn           音符场景
DiffCard.tscn       难度卡片场景
new-my_type/        谱面 JSON + manifest
addons/godot_mcp/   Godot MCP 插件（开发辅助）
```

## 谱面格式

`manifest.json`

```json
[
  {
    "folder": "song-folder",
    "title": "Song",
    "artist": "Artist",
    "audio": "audio.ogg",
    "difficulties": [
      {"name": "Easy", "stars": 1, "notes_count": 478}
    ]
  }
]
```

`<folder>/<Diff>.json`

```json
{
  "metadata": {"title": "Song", "version": "Easy"},
  "timing_points": [{"time": 0.45, "bpm": 145.0}],
  "notes": [
    {"time": 0.45, "lane": 0, "type": "tap", "end_time": 0.45},
    {"time": 0.864, "lane": 3, "type": "hold", "end_time": 1.277}
  ]
}
```

## 导出

仓库不包含 `export_presets.cfg`（其中有签名密码）。

```bat
copy export_presets.example.cfg export_presets.cfg
```

然后填入你自己的 keystore 路径与密码，用 Godot 导出 Android APK。

> 注意：keystore、APK、音频文件都不会上传到仓库。

## 说明

`main.gd` 是早期代码绘制版本，仅作参考，当前入口是 `MenuController.gd`。
