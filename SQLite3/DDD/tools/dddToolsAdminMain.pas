unit dddToolsAdminMain;

{$I Synopse.inc} // define HASINLINE USETYPEINFO CPU32 CPU64 OWNNORMTOUPPER

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, mORMotUI, mORMotUILogin, mORMotToolbar, SynTaskDialog,
  SynCommons, mORMot, mORMotHttpClient,
  mORMotDDD, dddInfraApps,
  dddToolsAdminDB, dddToolsAdminLog;

type
  TAdminControl = class(TWinControl)
  protected
    fClient: TSQLHttpClientWebsockets;
    fAdmin: IAdministratedDaemon;
    fDatabases: TRawUTF8DynArray;
    fPage: TSynPager;
    fPages: array of TSynPage;
    fLogFrame: TLogFrame;
    fDBFrame: TDBFrameDynArray;
    fDefinition: TDDDRestClientSettings;
  public
    LogFrameClass: TLogFrameClass;
    DBFrameClass: TDBFrameClass;
    Version: Variant;
    destructor Destroy; override;
    function Open(Definition: TDDDRestClientSettings): boolean;
    procedure Show;
    function GetState: Variant;
    procedure EndLog;
    procedure FormKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    property LogFrame: TLogFrame read fLogFrame;
    property DBFrame: TDBFrameDynArray read fDBFrame;
  end;

  TAdminForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  protected
    fFrame: TAdminControl;
  public
    property Frame: TAdminControl read fFrame;
  end;

var
  AdminForm: TAdminForm;

function AskForUserIfVoid(Definition: TDDDRestClientSettings): boolean;


implementation

{$R *.dfm}

function AskForUserIfVoid(Definition: TDDDRestClientSettings): boolean;
var U,P: string;
begin
  result := false;
  if Definition.ORM.User='' then
    if TLoginForm.Login(Application.Mainform.Caption,Format('Credentials for %s',
        [Definition.ORM.ServerName]),U,P,true,'') then begin
      Definition.ORM.User := StringToUTF8(U);
      Definition.ORM.PasswordPlain := StringToUTF8(P);
    end else
      exit;
  result := true;
end;

function TAdminControl.Open(Definition: TDDDRestClientSettings): boolean;
var temp: TForm;
    exec: TServiceCustomAnswer;
begin
  result := false;
  if Assigned(fAdmin) or (Definition.Orm.User='') then
    exit;
  try
    temp := CreateTempForm(Format('Connecting to %s...',[Definition.ORM.ServerName]));
    try
      Application.ProcessMessages;
      fClient := AdministratedDaemonClient(Definition);
      fClient.Services.Resolve(IAdministratedDaemon,fAdmin);
      exec := fAdmin.DatabaseExecute('','#version');
      version := _JsonFast(exec.Content);
      fDefinition := Definition;
      result := true;
    finally
      temp.Free;
    end;
  except
    on E: Exception do begin
      ShowException(E);
      FreeAndNil(fClient);
    end;
  end;
end;

function TAdminControl.GetState: Variant;
var exec: TServiceCustomAnswer;
begin
  if fAdmin<>nil then begin
    exec := fAdmin.DatabaseExecute('','#state');
    result := _JsonFast(exec.Content);
  end;
end;

procedure TAdminControl.Show;
var i,n: integer;
begin
  if (fClient=nil) or (fAdmin=nil) or (fPage<>nil) then
    exit; // show again after hide
  if LogFrameClass=nil then
    LogFrameClass := TLogFrame;
  if DBFrameClass=nil then
    DBFrameClass := TDBFrame;
  fDatabases := fAdmin.DatabaseList;
  fPage := TSynPager.Create(self);
  fPage.ControlStyle := fPage.ControlStyle+[csClickEvents]; // enable OnDblClick
  fPage.Parent := self;
  fPage.Align := alClient;
  n := length(fDatabases);
  SetLength(fPages,n+1);
  fPages[0] := TSynPage.Create(self);
  fPages[0].Caption := 'log';
  fPages[0].PageControl := fPage;
  fLogFrame := LogFrameClass.Create(self);
  fLogFrame.Parent := fPages[0];
  fLogFrame.Align := alClient;
  fLogFrame.Admin := fAdmin;
  if n>0 then begin
    SetLength(fDBFrame,n);
    for i := 0 to n-1 do begin
      fPages[i+1] := TSynPage.Create(self);
      fPages[i+1].Caption := UTF8ToString(fDatabases[i]);
      fPages[i+1].PageControl := fPage;
      if i=0 then
        fPage.ActivePageIndex := 1;
      fDBFrame[i] := DBFrameClass.Create(self);
      with fDBFrame[i] do begin
        Name := format('DBFrame%d',[i]);
        Parent := fPages[i+1];
        Align := alClient;
        DatabaseName := fDatabases[i];
        Admin := fAdmin;
        Open;
      end;
    end;
    Application.ProcessMessages;
    fDBFrame[0].mmoSQL.SetFocus;
  end;
end;

procedure TAdminControl.EndLog;
begin
  if fLogFrame<>nil then
  try
    Screen.Cursor := crHourGlass;
    if fLogFrame.Callback<>nil then
      fClient.Services.CallBackUnRegister(fLogFrame.Callback);
    fLogFrame.Closing;
  finally
    Screen.Cursor := crDefault;
  end;
end;

destructor TAdminControl.Destroy;
var i: integer;
begin
  if fLogFrame<>nil then begin
    Endlog;
    fLogFrame.Admin := nil;
    fLogFrame := nil;
  end;
  for i := 0 to high(fDBFrame) do
    fDBFrame[i].Admin := nil;
  fDBFrame := nil;
  fAdmin := nil;
  fDefinition.Free;
  FreeAndNil(fClient);
  inherited Destroy;
end;

procedure TAdminControl.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var pageIndex: integer;
begin
  pageIndex := fPage.ActivePageIndex;
  if pageIndex=0 then // log keys
    case Key of
    VK_F3:
      fLogFrame.btnSearchNextClick(fLogFrame.btnSearchNext);
    ord('A')..ord('Z'),Ord('0')..ord('9'),32:
      if (shift=[]) and not fLogFrame.edtSearch.Focused then
        fLogFrame.edtSearch.Text := fLogFrame.edtSearch.Text+string(Char(Key)) else
      if (key=ord('F')) and (ssCtrl in Shift) then begin
        fLogFrame.edtSearch.SelectAll;
        fLogFrame.edtSearch.SetFocus;
      end;
    end else
  if pageIndex<=Length(fDBFrame) then
    with fDBFrame[pageIndex-1] do
    case Key of
    VK_RETURN:
    if (shift=[]) and (mmoSQL.SelLength=0) then begin
      btnExecClick(nil);
      Key := 0;
    end;
    VK_F9:
      btnExecClick(btnExec);
    ord('A'):
      if ssCtrl in Shift then begin
        mmoSQL.SelectAll;
        mmoSQL.SetFocus;
      end;
    ord('H'):
      if ssCtrl in Shift then
        btnHistoryClick(btnHistory);
    end;
end;


{ TAdminForm }

procedure TAdminForm.FormCreate(Sender: TObject);
begin
  DefaultFont.Name := 'Tahoma';
  DefaultFont.Size := 9;
  Caption := Format('%s %s',[ExeVersion.ProgramName,ExeVersion.Version.Detailed]);
  fFrame := TAdminControl.Create(self);
  fFrame.Parent := self;
  fFrame.Align := alClient;
  OnKeyDown := fFrame.FormKeyDown;
end;

procedure TAdminForm.FormShow(Sender: TObject);
begin
  fFrame.Show;
  Caption := Format('%s - %s %s via %s',[ExeVersion.ProgramName,
    fFrame.version.prog,fFrame.version.version,fFrame.fDefinition.ORM.ServerName]);
end;

end.

