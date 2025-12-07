[Setup]
AppId={{F47AC10B-58CC-4372-A567-0E62B2C3D479}
AppVersion={#APP_VERSION}
AppName=SkyPort
AppPublisher=StarSphere
AppPublisherURL=https://github.com/StarSphere-1024/SkyPort
AppSupportURL=https://github.com/StarSphere-1024/SkyPort
AppUpdatesURL=https://github.com/StarSphere-1024/SkyPort
DefaultDirName={pf}\SkyPort
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={#OUTPUT_BASE_FILENAME}
Compression=lzma
SolidCompression=yes
; SetupIconFile=windows\packaging\exe\icon.ico
WizardStyle=modern
; 权限固定为 admin，避免无效占位符导致编译失败
PrivilegesRequired=admin
ArchitecturesAllowed=x64 arm64
ArchitecturesInstallIn64BitMode=x64 arm64

[Code]
procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['SkyPort.exe'];

  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function InitializeSetup(): Boolean;
begin
  KillProcesses;
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chineseSimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
[Files]
; 安装源目录由 ISCC /DSOURCE_DIR 参数传入
Source: "{#SOURCE_DIR}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\SkyPort"; Filename: "{app}\\SkyPort.exe"
Name: "{autodesktop}\\SkyPort"; Filename: "{app}\\SkyPort.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\\SkyPort.exe"; Description: "{cm:LaunchProgram,SkyPort}"; Flags: runascurrentuser nowait postinstall skipifsilent