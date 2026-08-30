; DeskTile Windows 当前用户安装器。
; 从发布页首次安装时使用 LocalAppData；应用内升级会通过 /DIR 覆盖当前程序目录。

#ifndef AppVersion
  #define AppVersion "1.2.6"
#endif

[Setup]
AppId={{A617E5B8-79C1-4B1E-9D52-16CB3A982026}
AppName=DeskTile 课表岛
AppVersion={#AppVersion}
AppPublisher=DeskTile
AppPublisherURL=https://github.com/GodBook/DeskTile
AppSupportURL=https://github.com/GodBook/DeskTile/issues
DefaultDirName={localappdata}\Programs\DeskTile
DefaultGroupName=DeskTile 课表岛
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SourceDir=..
OutputDir=dist
OutputBaseFilename=DeskTile-v{#AppVersion}-windows-x64-setup
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\desktile.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
Uninstallable=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\DeskTile 课表岛"; Filename: "{app}\desktile.exe"
Name: "{autodesktop}\DeskTile 课表岛"; Filename: "{app}\desktile.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："; Flags: unchecked

[Run]
Filename: "{app}\desktile.exe"; Description: "启动 DeskTile 课表岛"; Flags: nowait postinstall skipifsilent
