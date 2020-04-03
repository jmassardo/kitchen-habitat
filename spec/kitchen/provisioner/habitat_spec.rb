require_relative "../../spec_helper"

require "logger"
require "stringio"

require "kitchen/configurable"
require "kitchen/logging"
require "kitchen/provisioner/habitat"
require "kitchen/driver/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

def wrap_command(code, left_pad_length = 10)
  left_padded_code = code.map do |line|
    line.rjust(line.length + left_pad_length)
  end.join("\n")
  command = "#{left_padded_code}\n"
  command
end

describe Kitchen::Provisioner::Habitat do
  let(:logged_output)   { StringIO.new }
  let(:logger)          { Logger.new(logged_output) }
  let(:lifecycle_hooks) { Kitchen::LifecycleHooks.new({}) }
  let(:config)          { { kitchen_root: "/kroot" } }
  let(:platform)        { Kitchen::Platform.new(name: "fooos-99") }
  let(:suite)           { Kitchen::Suite.new(name: "suitey") }
  let(:verifier)        { Kitchen::Verifier::Dummy.new }
  let(:driver)          { Kitchen::Driver::Dummy.new }
  let(:transport)       { Kitchen::Transport::Dummy.new }
  let(:state_file)      { double("state_file") }

  let(:provisioner_object) { Kitchen::Provisioner::Habitat.new(config) }

  let(:provisioner) do
    p = provisioner_object
    instance
    p
  end

  let(:instance) do
    Kitchen::Instance.new(
      verifier:  verifier,
      driver: driver,
      logger: logger,
      lifecycle_hooks: lifecycle_hooks,
      suite: suite,
      platform: platform,
      provisioner: provisioner_object,
      transport: transport,
      state_file: state_file
    )
  end

  it "driver api_version is 2" do
    expect(provisioner.diagnose_plugin[:api_version]).to eq(2)
  end

  describe "#windows_install_cmd" do
    it "generates a valid install script" do
      config[:hab_channel] = "stable"
      config[:hab_version] = "1.5.29"
      windows_install_cmd = provisioner.send(
        :windows_install_cmd
      )
      expected_code = [
        "if ((Get-Command hab -ErrorAction Ignore).Path) {",
        "  Write-Output \"Habitat CLI already installed.\"",
        "} else {",
        "  Set-ExecutionPolicy Bypass -Scope Process -Force",
        "  $InstallScript = ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1'))",
        "  Invoke-Command -ScriptBlock ([scriptblock]::Create($InstallScript)) -ArgumentList stable, 1.5.29",
        "}",
      ]
      expect(windows_install_cmd).to eq(wrap_command(expected_code, 8))
    end
  end

  describe "#linux_install_cmd" do
    it "generates a valid install script" do
      config[:hab_version] = "1.5.29"
      linux_install_cmd = provisioner.send(
        :linux_install_cmd
      )
      expected_code = [
        "if command -v hab >/dev/null 2>&1",
        "then",
        "  echo \"Habitat CLI already installed.\"",
        "else",
        "  curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'",
        "  sudo -E bash /tmp/install.sh -v 1.5.29",
        "fi",
      ]
      expect(linux_install_cmd).to eq(wrap_command(expected_code, 8))
    end
  end

  describe "#windows_install_service" do
    it "generates a valid service install script" do
      config[:channel] = "stable"
      windows_install_service = provisioner.send(
        :windows_install_service
      )
      expected_code = [
        "New-Item -Path C:\\Windows\\Temp\\kitchen -ItemType Directory -Force | Out-Null",
        "New-Item -Path C:\\Windows\\Temp\\kitchen\\config -ItemType Directory -Force | Out-Null",
        "if (!($env:Path | Select-String \"Habitat\")) {",
        "  $env:Path += \";C:\\ProgramData\\Habitat\"",
        "}",
        "if (!(Get-Service -Name Habitat -ErrorAction Ignore)) {",
        "  hab license accept",
        "  Write-Output \"Installing Habitat Windows Service\"",
        "  hab pkg install core/windows-service",
        "  if ($(Get-Service -Name Habitat).Status -ne \"Stopped\") {",
        "    Stop-Service -Name Habitat",
        "  }",
        "  $HabSvcConfig = \"c:\\hab\\svc\\windows-service\\HabService.dll.config\"",
        "  [xml]$xmlDoc = Get-Content $HabSvcConfig",
        "  $obj = $xmlDoc.configuration.appSettings.add | where {$_.Key -eq \"launcherArgs\" }",
        "  $obj.value = \"--no-color --channel stable\"",
        "  $xmlDoc.Save($HabSvcConfig)",
        "  Start-Service -Name Habitat",
        "}",
      ]
      expect(windows_install_service).to eq(wrap_command(expected_code, 8))
    end
  end

  describe "#supervisor_options" do
    it "sets the --listen-ctl flag when config[:hab_sup_listen_ctl] is set" do
      config[:hab_sup_listen_ctl] = "0.0.0.0:9632"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--listen-ctl 0.0.0.0:9632")
    end

    it "doesn't set the --listen-ctl flag when config[:hab_sup_listen_ctl] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--listen-ctl 0.0.0.0:9632")
    end

    it "sets the --ring flag when config[:hab_sup_ring] is set" do
      config[:hab_sup_ring] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--ring test")
    end

    it "doesn't set the --ring flag when config[:hab_sup_ring] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--ring test")
    end
  end
end
