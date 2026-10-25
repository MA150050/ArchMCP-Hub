<div dir="rtl" align="center">

![ArchMCP Hub v1.0.0 Banner](assets/branding/github-banner.svg)

# ArchMCP Hub — الإصدار الرسمي العام الأول (`v1.0.0`)

**مركز تحكم مكتبي محلي لنظام Windows لإدارة وتثبيت وإصلاح وتعطيل/إزالة وفحص تكاملات بروتوكول Model Context Protocol (MCP) لبرامج التصميم المعماري والهندسي والنمذجة ثلاثية الأبعاد**

[![Release](https://img.shields.io/badge/Release-v1.0.0-30B4A9?style=flat-square&logo=github)](RELEASE-NOTES-v1.0.0.md)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20(x64)-0078D6?style=flat-square&logo=windows)](docs/installation/INSTALLATION.md)
[![Framework](https://img.shields.io/badge/.NET-10.0%20WPF-512BD4?style=flat-square&logo=dotnet)](src/ArchMCP.Hub.App/ArchMCP.Hub.App.csproj)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20(7--bit%20ASCII)-5391FE?style=flat-square&logo=powershell)](scripts/)
[![Contract Tests](https://img.shields.io/badge/Contract%20Tests-14%2F14%20Passed-2EA043?style=flat-square)](docs/TEST-PLAN.md)
[![License](https://img.shields.io/badge/License-Proprietary%20(All%20Rights%20Reserved)-FD921E?style=flat-square)](LICENSE)

[**English Documentation (README.md)**](README.md) · [**دليل التثبيت**](docs/installation/INSTALLATION.md) · [**دليل الاستخدام**](docs/usage/USER-GUIDE.md) · [**مصفوفة التوافق**](docs/compatibility/COMPATIBILITY.md) · [**المعمارية**](docs/architecture/ARCHITECTURE.md) · [**استكشاف الأخطاء**](docs/troubleshooting/TROUBLESHOOTING.md) · [**سجل التغييرات**](CHANGELOG.md)

</div>

---

<div dir="rtl">

## جدول المحتويات

1. [نظرة عامة والهدف من المشروع](#1-نظرة-عامة-والهدف-من-المشروع)
2. [أبرز المميزات المعتمدة في الإصدار v1.0.0](#2-أبرز-المميزات-المعتمدة-في-الإصدار-v100)
3. [البرامج الهندسية والمعمارية المدعومة](#3-البرامج-الهندسية-والمعمارية-المدعومة)
4. [وكلاء الذكاء الاصطناعي المدعومون (AI Clients)](#4-وكلاء-الذكاء-الاصطناعي-المدعومون-ai-clients)
5. [المعمارية الهندسية ودورة عمل التكامل](#5-المعمارية-الهندسية-ودورة-عمل-التكامل)
6. [متطلبات التشغيل](#6-متطلبات-التشغيل)
7. [طريقة التشغيل والتثبيت خطوة بخطوة](#7-طريقة-التشغيل-والتثبيت-خطوة-بخطوة)
8. [تفعيل جسر الاتصال داخل البرامج الهندسية وفحص الحالة (Verify)](#8-تفعيل-جسر-الاتصال-داخل-البرامج-الهندسية-وفحص-الحالة-verify)
9. [مصفوفة التوافق ومستويات التحقق](#9-مصفوفة-التوافق-ومستويات-التحقق)
10. [استكشاف الأخطاء وإصلاحها](#10-استكشاف-الأخطاء-وإصلاحها)
11. [هيكل المستودع](#11-هيكل-المستودع)
12. [البناء من المصدر (Build from Source)](#12-البناء-من-المصدر-build-from-source)
13. [الأمان والصلاحيات والخصوصية](#13-الأمان-والصلاحيات-والخصوصية)
14. [الملكية الفكرية والترخيص](#14-الملكية-الفكرية-والترخيص)
15. [الدعم والمساهمة](#15-الدعم-والمساهمة)

---

## 1. نظرة عامة والهدف من المشروع

يُعد **ArchMCP Hub (`v1.0.0`)** تطبيق سطح مكتب محليًا لنظام Windows (مبنيًا باستخدام **C# / .NET 10 WPF** و**Windows PowerShell 5.1+**) صُمم لتوحيد وتسهيل عملية اكتشاف وتثبيت وإعداد وإصلاح وتعطيل/إزالة وفحص جسور بروتوكول **Model Context Protocol (MCP)** بين برامج التصميم المعماري والهندسي (**Revit**، **Rhino**، **3ds Max**، **AutoCAD**، **SketchUp**) ووكلاء الذكاء الاصطناعي (**OpenCode**، **Claude Desktop**، **Claude Code**، **OpenAI Codex**، **Google Antigravity**).

يعمل التطبيق بالكامل محليًا على جهاز المستخدم دون الحاجة إلى أي حساب سحابي أو صلاحيات مسؤول النظام (Administrator)، مع نظام نسخ احتياطي واستعادة تلقائية (`Backup & Rollback`) يحافظ على إعدادات المستخدم الحالية.

---

## 2. أبرز المميزات المعتمدة في الإصدار v1.0.0

- **فحص حقيقي للبرامج المثبتة (`EnvironmentScanner`)**:
  يكتشف الإصدارات المثبتة فعليًا عبر فحص مجلدات `Program Files` وسجلات التثبيت في Windows مع التحقق من وجود ملف التشغيل الفعلي (`Revit.exe`، `Rhino.exe`، `3dsmax.exe`، `acad.exe`، `SketchUp.exe`) وتجاهل الإضافات الفرعية أو السجلات القديمة.
- **أربعة إجراءات متكاملة لكل برنامج ووكيل ذكاء اصطناعي**:
  - **تثبيت وربط (`Install & connect`)**
  - **تعطيل / إلغاء تثبيت (`Disable / Uninstall`)**
  - **إصلاح (`Repair`)**
  - **فحص (`Verify`)**
  مع تحديث تلقائي لحالة البرنامج في الواجهة فور إغلاق نافذة PowerShell.
- **واجهة ثنائية اللغة (عربي / إنجليزي) مع الوضع الداكن والفاتح**:
  تبديل فوري بين العربية والإنجليزية (`EN / عربي`) وبين الوضع الداكن والوضع الفاتح، مع دمج الأيقونة الرسمية الجديدة للتطبيق (`ArchMCP.ico` متعددة الدقات من `16x16` حتى `256x256`).
- **دعم الإصدارات القديمة والحديثة للبرامج الهندسية**:
  - **Revit 2022–2027**: يتضمن معالجة تلقائية لتوافق `ElementId` (`Apply-Revit2022CompatibilityPatch`) لدعم `.IntegerValue` (في إصداري 2022 و2023) إلى جانب `.Value` (في إصدارات 2024–2027).
  - **Rhino 7 & Rhino 8**: يدعم Rhino 8 عبر مدير الحزم Yak (`jingcheng-chen/rhinomcp` على المنفذ `1999`)، ويدعم Rhino 7 عبر بيئة Python 3.12 معزولة (`Initialize-ArchMcpPipEnv`) وجسر `rhino_mcp_bridge.py` (`reer-ide/rhino_mcp`).
  - **3ds Max 2021–2027**: ينشر إضافة C++ GUP للإصدارات 2023–2027 بالإضافة إلى سكربت بدء التشغيل التلقائي `mcp_server.ms` على المنفذ `8765` لجميع الإصدارات 2021–2027 مع تفعيل الوضع الآمن (`safe_mode = true`).
  - **SketchUp 2021–2026**: يعالج تلقائيًا هيكل إضافة Ruby (`Resolve-SketchUpRubyPluginSource`) لضمان نشر `su_mcp.rb` و`su_mcp/main.rb` في المسار الصحيح دون تداخل، وينشئ مشغّل Python 3.12 مباشر (`archmcp_sketchup_server.py`) مع فحص مصافحة `stdio` قبل التسجيل.
- **توافق كامل مع Windows PowerShell 5.1**:
  جميع ملفات `.ps1` مكتوبة بترميز 7-bit ASCII نقي (مفحوصة آليًا) لمنع أخطاء الترميز في Windows PowerShell 5.1، مع إبقاء نافذة الأوامر مفتوحة عبر `Wait-ArchMcpWindowClose` حتى يضغط المستخدم Enter.

---

## 3. البرامج الهندسية والمعمارية المدعومة

| البرنامج الهندسي (Host) | الإصدارات المدعومة | الإصدارات غير المدعومة | المستودع المصدري (Upstream) | الترخيص | آلية النقل وجسر الاتصال |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Autodesk Revit** | **2022 – 2027** | 2021 والأقدم | [`Demolinator/revit-mcp-server`](https://github.com/Demolinator/revit-mcp-server) | MIT | `stdio` ← FastMCP ← HTTP `:48884` ← `pyRevit` Routes (`revit-mcp.extension`) |
| **Rhinoceros 3D** | **Rhino 7 & Rhino 8** | Rhino 6 والأقدم | [`jingcheng-chen/rhinomcp`](https://github.com/jingcheng-chen/rhinomcp) (8)<br>[`reer-ide/rhino_mcp`](https://github.com/reer-ide/rhino_mcp) (7) | MIT | `stdio` ← Python MCP ← TCP `:1999` (Rhino 8 Yak) / `:9877` (`rhino_mcp_bridge.py` في Rhino 7) |
| **Autodesk 3ds Max** | **2021 – 2027** | 2020 والأقدم | [`cl0nazepamm/3dsmax-mcp`](https://github.com/cl0nazepamm/3dsmax-mcp) | MIT | `stdio` ← FastMCP ← Named Pipe (2023+) / MAXScript TCP `:8765` (2021–2027) |
| **Autodesk AutoCAD** | **2021 – 2027** | 2020 والأقدم | [`U-C4N/Autocad-MCP`](https://github.com/U-C4N/Autocad-MCP) | MIT | `stdio` ← FastMCP ← اتصال ActiveX/COM مباشر + محرك `ezdxf` المباشر |
| **SketchUp** | **2021 – 2026** | 2020 والأقدم | [`NeoNexAI/sketchup-mcp`](https://github.com/NeoNexAI/sketchup-mcp) | MIT | `stdio` ← FastMCP ← TCP `127.0.0.1:9876` ← إضافة Ruby (`su_mcp.rb` + `su_mcp/main.rb`) |

---

## 4. وكلاء الذكاء الاصطناعي المدعومون (AI Clients)

- **OpenCode**: التسجيل عبر أداة CLI (`opencode mcp add --global`) ودمج الإعدادات في `~/.config/opencode/opencode.json`.
- **Claude Desktop**: يدعم إصدار متجر Microsoft الحديثة (Claude Desktop 3.x MSIX في `%LOCALAPPDATA%\Claude-Data\claude_*\claude_desktop_config.json`) والإصدارات القياسية (`%APPDATA%\Claude\claude_desktop_config.json`)، مع تشغيل مفسر `.venv\Scripts\python.exe` مباشرةً، وكتابة JSON بترميز UTF-8 بدون BOM، والتحقق من مصافحة `stdio` قبل الحفظ.
- **Claude Code**: التسجيل عبر CLI (`claude mcp add --scope user`) وتحديث `~/.claude.json`.
- **OpenAI Codex**: التسجيل عبر CLI (`codex mcp add`) ودمج قسم `[mcp_servers.<name>]` في `~/.codex/config.toml`.
- **Google Antigravity**: تحديث `~/.gemini/config/mcp_config.json` (ومسار `~/.gemini/antigravity/mcp_config.json` إن وُجد) مع إنشاء بيئة `.venv-modern` (MCP SDK 2.x) ومحوّل التوافق `scripts/shims/archmcp_mcp2_entry.py` لدعم بروتوكول `2026-07-28` (`server/discover`).

---

## 5. المعمارية الهندسية ودورة عمل التكامل

![ArchMCP Hub System Architecture](assets/branding/architecture-diagram.svg)

![ArchMCP Hub Integration Workflow](assets/branding/integration-workflow.svg)

للاطلاع على التفاصيل المعمارية الكاملة وسجل القرارات الهندسية، راجع [`docs/architecture/ARCHITECTURE.md`](docs/architecture/ARCHITECTURE.md) و[`docs/DECISIONS.md`](docs/DECISIONS.md).

---

## 6. متطلبات التشغيل

- **نظام التشغيل**: Windows 10 أو Windows 11 (معمارية 64-بت `win-x64`).
- **PowerShell**: Windows PowerShell 5.1 (مدمج في Windows) أو PowerShell 7+.
- **بيئة .NET**: `.NET 10.0` (أو `.NET 8.0+`؛ يقوم `Run-ArchMCP-Hub.bat` بتحميل نسخة محلية تلقائيًا في `.tools\dotnet` إذا لم تكن مثبتة على الجهاز).
- **أداة `uv` وبيئات Python**: يتم تحميل `uv.exe` تلقائيًا في مسار المستخدم `%LOCALAPPDATA%\ArchMCP Hub\Tools\uv\uv.exe` دون الحاجة إلى تثبيت Python يدويًا أو صلاحيات مسؤول.
- **متطلبات خاصة بـ Revit**: يتطلب تثبيت إضافة **[pyRevit](https://github.com/pyrevitlabs/pyRevit/releases/latest)** (`v4.8.16+` أو `v5.x`).

---

## 7. طريقة التشغيل والتثبيت خطوة بخطوة

1. فك ضغط مجلد `ArchMCP-Hub-v1.0.0` في أي مسار محلي على جهازك.
2. شغّل الملف **`Run-ArchMCP-Hub.bat`** بالنقر المزدوج:
   ```bat
   Run-ArchMCP-Hub.bat
   ```
3. سيقوم السكربت باستعادة الحزم وبناء الحل وتشغيل الاختبارات ونشر النسخة المحمولة في `dist\win-x64\ArchMCP.Hub.exe` ثم فتح نافذة البرنامج تلقائيًا.
4. من القائمة الجانبية، انتقل إلى **Integrations (`التكاملات`)**، واختر البرنامج الهندسي وإصداره، ثم اختر وكيل الذكاء الاصطناعي من قائمة **AI AGENT**، واضغط على **Install & connect (`تثبيت وربط`)**.

راجع [`docs/installation/INSTALLATION.md`](docs/installation/INSTALLATION.md) و[`docs/usage/USER-GUIDE.md`](docs/usage/USER-GUIDE.md) للشرح التفصيلي.

---

## 8. تفعيل جسر الاتصال داخل البرامج الهندسية وفحص الحالة (Verify)

لا يمنح ArchMCP Hub حالة **`Verified (متصل)`** إلا عندما يكون البرنامج الهندسي مفتوحًا ويستجيب جسر الاتصال الداخلي:

- **Autodesk Revit (2022–2027)**: افتح مشروعًا داخل Revit. إذا كان Revit مفتوحًا أثناء التثبيت، اختر من شريط **pyRevit → Reload** لتشغيل خادم Routes على المنفذ `48884`، ثم اضغط **Verify**.
- **Rhinoceros 8**: افتح Rhino 8 واكتب الأمر `mcpstart` في شريط الأوامر لتفعيل المنفذ `1999`، ثم اضغط **Verify**.
- **Rhinoceros 7**: افتح Rhino 7 واختر `Tools -> PythonScript -> Run...` ثم شغّل الملف `%APPDATA%\McNeel\Rhinoceros\7.0\scripts\rhino_mcp_bridge.py`، ثم اضغط **Verify**.
- **Autodesk 3ds Max (2021–2027)**: أعد تشغيل 3ds Max بعد التثبيت ليتم تحميل `mcp_server.ms` / `mcp_bridge.gup` تلقائيًا على المنفذ `8765`، ثم اضغط **Verify**.
- **Autodesk AutoCAD (2021–2027)**: يعمل وضع `ezdxf` لملفات DXF فورًا دون فتح البرنامج؛ وللتحكم الحي عبر COM في ملفات DWG افتح AutoCAD مع لوحة رسم نشطة ثم اضغط **Verify**.
- **SketchUp (2021–2026)**: افتح SketchUp ومن القائمة العلوية اختر `Extensions -> SketchUp MCP -> Start Server` لتشغيل المنفذ `9876`، ثم اضغط **Verify**.

---

## 9. مصفوفة التوافق ومستويات التحقق

يميز المشروع بدقة بين **الدعم البرمجي المُنفَّذ (Implemented Support)** وبين **التوافق المُتحقَّق منه فعليًا (Verified Compatibility)**. راجع [`docs/compatibility/COMPATIBILITY.md`](docs/compatibility/COMPATIBILITY.md) و[`docs/COMPATIBILITY-MATRIX.csv`](docs/COMPATIBILITY-MATRIX.csv) و[`docs/AI-CLIENT-MATRIX.csv`](docs/AI-CLIENT-MATRIX.csv) للتفاصيل الكاملة.

> **ملاحظة مهمة حول AutoCAD مع Google Antigravity**: يعتمد الخادم المصدري `U-C4N/Autocad-MCP` حاليًا على مكتبة `fastmcp 3.x` الداخلية التي ترفض طلب `server/discover` الخاص ببروتوكول MCP `2026-07-28` في Google Antigravity؛ بينما يعمل AutoCAD MCP Pro بكفاءة مع **OpenCode** و**Claude Desktop**.

---

## 10. استكشاف الأخطاء وإصلاحها

- **عدم ظهور الأدوات في Claude Desktop بعد التثبيت**:
  أغلق Claude Desktop بالكامل من أيقونة شريط المهام المصغّر (System Tray -> Right-click -> **Quit**) ثم أعد فتحه؛ إغلاق النافذة فقط لا يعيد قراءة ملف الإعدادات.
- **مشكلة `Error Loading File su_mcp/main` في SketchUp**:
  اضغط على زر **Repair (`إصلاح`)** في ArchMCP Hub v1.0.0 ليقوم `Resolve-SketchUpRubyPluginSource` بتنظيف أي مجلدات متداخلة أو ملفات نسخ احتياطي وإعادة نشر `su_mcp.rb` و`su_mcp/main.rb` في المسار الصحيح.
- **فتح مجلد السجلات التشخيصية**:
  من تبويب **Activity & Logs (`النشاط والسجلات`)** اضغط على **Open diagnostic log folder (`فتح مجلد السجلات`)** لفتح `%LOCALAPPDATA%\ArchMCP Hub\Logs\`.

للمزيد راجع [`docs/troubleshooting/TROUBLESHOOTING.md`](docs/troubleshooting/TROUBLESHOOTING.md).

---

## 11. هيكل المستودع

يتبع المستودع تنظيمًا هندسيًا واضحًا يضم:
- `src/ArchMCP.Hub.App/`: تطبيق سطح المكتب بواجهة WPF وأيقونة `Assets/ArchMCP.ico` و`Assets/ArchMCP.png`.
- `src/ArchMCP.Hub.Core/`: مكتبة فحص البيئة (`EnvironmentScanner.cs`) وحل التوافق (`Compatibility.cs`).
- `scripts/`: سكربتات PowerShell 5.1+ للتثبيت والإصلاح والفحص والإزالة ومحوّل `scripts/shims/archmcp_mcp2_entry.py`.
- `registry/`: سجل التكاملات `integrations.json` ومخطط JSON Schema (`integration-registry.schema.json`).
- `tests/`: اختبارات الوحدة xUnit (`ArchMCP.Hub.Core.Tests`) واختبارات العقود والترميز (`run_all_tests.py`، `test_claude_desktop.ps1`، `test_rhino_env.ps1`).
- `assets/`: الهوية البصرية والشعارات (`github-banner.svg`، `social-preview.svg`، `architecture-diagram.svg`، `integration-workflow.svg`، `icons/`).
- `docs/`: الأدلة التفصيلية للتثبيت والاستخدام والتوافق والمعمارية واستكشاف الأخطاء.

---

## 12. البناء من المصدر (Build from Source)

```powershell
dotnet restore .\ArchMCP.Hub.sln
dotnet build .\ArchMCP.Hub.sln -c Release --no-restore
dotnet test .\ArchMCP.Hub.sln -c Release --no-build
python .\tests\run_all_tests.py
dotnet publish .\src\ArchMCP.Hub.App\ArchMCP.Hub.App.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\dist\win-x64
```

---

## 13. الأمان والصلاحيات والخصوصية

- يعمل التطبيق محليًا بالكامل (`127.0.0.1`) ولا يرسل أي بيانات أو نماذج هندسية إلى أي خادم خارجي.
- لا يتطلب صلاحيات مسؤول النظام (`requiresElevation: false`).
- ينشئ نسخة احتياطية مؤرخة (`.backup-YYYYMMDD-HHMMSS`) قبل أي تعديل على ملفات الإعدادات مع استعادة تلقائية عند حدوث أي خطأ. راجع [`SECURITY.md`](SECURITY.md).

---

## 14. الملكية الفكرية والترخيص

- **المالك والمطور**: **Mohamed Abd El-Hafez**
- **حقوق النشر**: **Copyright © 2026 Mohamed Abd El-Hafez. All Rights Reserved.**
- **الترخيص**: ترخيص ملكية خاصة (جميع الحقوق محفوظة) — راجع ملف [`LICENSE`](LICENSE).
  - إتاحة هذا المستودع للعامة على GitHub لا تمنح أي إذن بنسخ الكود الأصلي أو تعديله أو إعادة توزيعه أو استغلاله تجاريًا دون إذن كتابي مسبق من المالك.
- **إشعارات الطرف الثالث**: تخضع خوادم MCP المصدرية والأدوات الخارجية لتراخيصها الخاصة الموضحة بالتفصيل في [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

---

## 15. الدعم والمساهمة

- راجع [`SUPPORT.md`](SUPPORT.md) و[`CONTRIBUTING.md`](CONTRIBUTING.md) و[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
- عند الإبلاغ عن مشكلة عبر قوالب GitHub Issues، احرص دائمًا على إزالة أي مفاتيح API أو رموز سرية من السجلات قبل نشرها.

</div>
