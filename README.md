# B-talk

> 说出来，直接可用。

[官方网站](https://b-talk-360337791388.us-west1.run.app/)

B-talk 是一款面向 macOS 的菜单栏语音输入与整理工具。它把语音转写、内容整理和结果落地串成一条连续工作流，让你可以用一次快捷键完成：

`唤起录音 -> 实时转写 -> 智能整理 -> 粘贴/保存`

## 项目定位

B-talk 不是单纯把语音变成文字，而是把口语内容整理成更适合继续工作的文本。

适合的场景包括：

- 灵感速记
- 会议整理
- 写作起草
- 需求描述
- 编程任务表达

## 当前能力

- 菜单栏常驻，支持全局热键启动/停止录音
- 实时显示录音和处理中状态的 HUD 浮窗
- 支持多种语音识别引擎
  - Apple Speech
  - Azure Speech
  - Deepgram
  - OpenAI Transcription
- 支持多种 LLM 提供商
  - Anthropic Claude
  - OpenAI
  - Google Gemini
  - OpenAI-compatible 接口
- 提供多种文本整理模板
  - Smart Auto-Detect
  - Requirement Description
  - Bug Report
  - Custom
- 支持结构化结果粘贴、原文粘贴、自动复制、Library 保存
- 支持快捷配置、权限检查与自定义热键

## 技术栈

- Swift
- SwiftUI
- macOS 14+
- AppKit
- 多家 STT / LLM API 集成

## 快速开始

### 环境要求

- macOS 14 或更高版本
- Xcode 16+ 或支持 Swift 6 的工具链

### 本地运行

```bash
swift build -c release
bash build.sh
open .build/B-talk.app
```

### 首次使用

首次启动后，需要根据系统提示授予以下权限：

- Microphone
- Input Monitoring
- Accessibility

如果你希望启用云端识别或整理能力，还需要在设置页中填入对应的 API Key。仓库不会包含任何真实密钥。

## 项目结构

```text
Sources/BTalk/
  App/            应用入口、全局状态、菜单栏
  Audio/          音频采集
  FloatingWindow/ HUD 浮窗
  HotKey/         全局快捷键
  LLM/            文本整理与模型接入
  Library/        历史记录存储与展示
  Networking/     HTTP / SSE / WebSocket
  Output/         光标粘贴与焦点追踪
  Settings/       设置、Keychain、快速配置
  STT/            语音识别提供商
Resources/
  Info.plist
```

## 开源说明

- 本仓库已移除本地构建产物和本地工具配置
- 不包含任何个人 API Key、Token 或私有服务凭据
- README 与品牌名称统一为 `B-talk`

## 路线图

- 更完整的多语言体验
- 更清晰的 Prompt 与场景模板体系
- 更好的结果确认与编辑体验
- 官方门户网站持续迭代与演示内容完善

## 官方网站

- 在线访问：[https://b-talk-360337791388.us-west1.run.app/](https://b-talk-360337791388.us-west1.run.app/)
- 门户网站用于展示产品定位、核心场景、工作流与下载入口

## License

暂未指定。若你准备将其作为正式开源项目对外发布，建议补充明确的开源许可证。
