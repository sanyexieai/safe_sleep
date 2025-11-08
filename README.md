# Safe Sleep - 睡眠监测应用

一个用于监测睡眠状况的Flutter Android应用。

## 功能特性

1. **录音功能** - 记录整晚的睡眠录音
2. **波形显示** - 将录音按时间轴显示为波形图
3. **异常检测** - 自动检测并整理异常声音（呼噜、磨牙、起夜等）
4. **异常列表** - 以列表形式展示所有检测到的异常声音片段
5. **扩展性** - 保留异常类型识别的接口，便于后续添加机器学习模型

## 技术栈

- Flutter 3.0+
- record - 音频录制
- fl_chart - 波形图表显示
- permission_handler - 权限管理
- path_provider - 文件路径管理

## 安装和运行

1. 确保已安装Flutter SDK（3.0或更高版本）
2. 运行以下命令安装依赖：
   ```bash
   flutter pub get
   ```
3. 连接Android设备或启动模拟器
4. 运行应用：
   ```bash
   flutter run
   ```

## 权限说明

应用需要以下权限：
- 麦克风权限：用于录音
- 存储权限：用于保存录音文件

首次使用时，应用会请求这些权限。

## 使用说明

1. **开始录音**：点击"开始录音"按钮开始记录睡眠
2. **停止录音**：点击"停止录音"按钮结束录音并保存
3. **查看详情**：点击录音列表中的任意记录查看波形和异常检测结果
4. **异常检测**：应用会自动分析录音并标记异常声音片段

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/
│   └── recording_session.dart  # 录音会话模型
├── screens/
│   ├── home_screen.dart        # 主界面
│   └── recording_detail_screen.dart  # 录音详情界面
└── services/
    ├── audio_recorder_service.dart    # 录音服务
    └── audio_analyzer_service.dart    # 音频分析服务
```

## 扩展性

`AnomalyType` 枚举已预留了多种异常类型：
- `snoring` - 呼噜
- `teethGrinding` - 磨牙
- `nightWaking` - 起夜
- `coughing` - 咳嗽
- `talking` - 说梦话

在 `audio_analyzer_service.dart` 中的 `_classifyAnomaly` 方法可以扩展为使用机器学习模型进行更精确的分类。

## 注意事项

- 当前版本的波形提取使用模拟数据，实际项目中应集成真实的音频解码库（如ffmpeg）
- 异常检测算法使用简单的阈值检测，可根据需求优化
- 录音文件保存在应用文档目录中

## 许可证

MIT License

