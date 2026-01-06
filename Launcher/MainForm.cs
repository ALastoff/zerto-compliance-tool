using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Linq;
using System.Windows.Forms;
using System.Security;
using System.Security.Principal;
using System.Runtime.InteropServices;

namespace ZertoComplianceLauncher
{
    public partial class MainForm : Form
    {
        private TextBox txtZvmaHost;
        private TextBox txtUsername;
        private TextBox txtPassword;
        private TextBox txtPeerHosts;
        private TextBox txtOutputPath;
        private CheckBox chkSchedule;
        private CheckBox chkInsecure;
        private CheckBox chkUseLtr;
        private CheckBox chkDifferentSecondaryAuth;
        private TextBox txtSecondaryUsername;
        private TextBox txtSecondaryPassword;
        private CheckBox chkAdditionalSites;
        private TextBox txtAdditionalSites;
        private ComboBox cmbScheduleFrequency;
        private Button btnBrowse;
        private Button btnRun;
        private Button btnSchedule;
        private Button btnCancel;
        private Button btnHelp;
        private Label lblStatus;
        private ProgressBar progressBar;
        private RichTextBox rtbOutput;

        public MainForm()
        {
            InitializeComponent();
            InitializeCustomComponents();
        }

        private void InitializeComponent()
        {
            this.Text = "Zerto Compliance Tool Launcher";
            this.Size = new System.Drawing.Size(620, 750);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = true;
        }

        private void InitializeCustomComponents()
        {
            // Menu
            var menu = new MenuStrip();
            var helpMenu = new ToolStripMenuItem("Help");
            var startHereItem = new ToolStripMenuItem("Start Here");
            startHereItem.Click += (s, e) =>
            {
                try
                {
                    string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                    string[] candidates = new[]
                    {
                        Path.Combine(exeDir, "START_HERE.md"),
                        Path.Combine(exeDir, "START_HERE.txt"),
                        Path.GetFullPath(Path.Combine(exeDir, "..", "START_HERE.md")),
                        Path.GetFullPath(Path.Combine(exeDir, "..", "START_HERE.txt")),
                        Path.GetFullPath(Path.Combine(exeDir, "..", "..", "START_HERE.md")),
                        Path.GetFullPath(Path.Combine(exeDir, "..", "..", "START_HERE.txt"))
                    };
                    string found = null;
                    foreach (var c in candidates)
                    {
                        if (File.Exists(c)) { found = c; break; }
                    }
                    if (found != null)
                    {
                        Process.Start(new ProcessStartInfo(found) { UseShellExecute = true });
                    }
                    else
                    {
                        MessageBox.Show("START_HERE.md not found in the application directory.", "Help", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Unable to open START_HERE: {ex.Message}", "Help", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
            helpMenu.DropDownItems.Add(startHereItem);
            menu.Items.Add(helpMenu);
            this.MainMenuStrip = menu;
            this.Controls.Add(menu);

            // Title Label
            Label lblTitle = new Label
            {
                Text = "Zerto Compliance Tool",
                Font = new System.Drawing.Font("Segoe UI", 16, System.Drawing.FontStyle.Bold),
                ForeColor = System.Drawing.Color.FromArgb(1, 169, 130),
                Location = new System.Drawing.Point(20, 20),
                Size = new System.Drawing.Size(550, 40),
                TextAlign = System.Drawing.ContentAlignment.MiddleCenter
            };
            this.Controls.Add(lblTitle);

            // ZVMA Host
            Label lblZvma = new Label { Text = "Source Site:", Location = new System.Drawing.Point(20, 80), Size = new System.Drawing.Size(120, 20) };
            txtZvmaHost = new TextBox { Location = new System.Drawing.Point(150, 78), Size = new System.Drawing.Size(400, 25), PlaceholderText = "192.168.111.20" };
            this.Controls.Add(lblZvma);
            this.Controls.Add(txtZvmaHost);

            // Username
            Label lblUser = new Label { Text = "Zerto GUI User Name:", Location = new System.Drawing.Point(20, 115), Size = new System.Drawing.Size(120, 20) };
            txtUsername = new TextBox { Location = new System.Drawing.Point(150, 113), Size = new System.Drawing.Size(400, 25), PlaceholderText = "admin" };
            this.Controls.Add(lblUser);
            this.Controls.Add(txtUsername);

            // Password
            Label lblPass = new Label { Text = "Password:", Location = new System.Drawing.Point(20, 150), Size = new System.Drawing.Size(120, 20) };
            txtPassword = new TextBox { Location = new System.Drawing.Point(150, 148), Size = new System.Drawing.Size(400, 25), UseSystemPasswordChar = true };
            this.Controls.Add(lblPass);
            this.Controls.Add(txtPassword);

            // Secondary Site (Optional)
            Label lblSecondary = new Label { Text = "Secondary Site:", Location = new System.Drawing.Point(20, 185), Size = new System.Drawing.Size(120, 20) };
            txtPeerHosts = new TextBox { Location = new System.Drawing.Point(150, 183), Size = new System.Drawing.Size(400, 25), PlaceholderText = "192.168.222.20" };
            this.Controls.Add(lblSecondary);
            this.Controls.Add(txtPeerHosts);

            // Secondary site different credentials checkbox
            chkDifferentSecondaryAuth = new CheckBox { Text = "Secondary site has different credentials", Location = new System.Drawing.Point(150, 210), Size = new System.Drawing.Size(320, 25) };
            chkDifferentSecondaryAuth.CheckedChanged += (s, e) =>
            {
                txtSecondaryUsername.Enabled = chkDifferentSecondaryAuth.Checked;
                txtSecondaryPassword.Enabled = chkDifferentSecondaryAuth.Checked;
            };
            this.Controls.Add(chkDifferentSecondaryAuth);

            // Secondary Username
            Label lblSecondaryUser = new Label { Text = "Secondary Username:", Location = new System.Drawing.Point(20, 240), Size = new System.Drawing.Size(130, 20) };
            txtSecondaryUsername = new TextBox { Location = new System.Drawing.Point(150, 238), Size = new System.Drawing.Size(400, 25), PlaceholderText = "admin@secondary.local", Enabled = false };
            this.Controls.Add(lblSecondaryUser);
            this.Controls.Add(txtSecondaryUsername);

            // Secondary Password
            Label lblSecondaryPass = new Label { Text = "Secondary Password:", Location = new System.Drawing.Point(20, 275), Size = new System.Drawing.Size(130, 20) };
            txtSecondaryPassword = new TextBox { Location = new System.Drawing.Point(150, 273), Size = new System.Drawing.Size(400, 25), UseSystemPasswordChar = true, Enabled = false };
            this.Controls.Add(lblSecondaryPass);
            this.Controls.Add(txtSecondaryPassword);

            // Output Path
            Label lblOutput = new Label { Text = "Output Folder:", Location = new System.Drawing.Point(20, 310), Size = new System.Drawing.Size(120, 20) };
            txtOutputPath = new TextBox { Location = new System.Drawing.Point(150, 308), Size = new System.Drawing.Size(340, 25), ReadOnly = true };
            txtOutputPath.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ZertoCompliance");
            btnBrowse = new Button { Text = "Browse...", Location = new System.Drawing.Point(495, 307), Size = new System.Drawing.Size(75, 27) };
            btnBrowse.Click += BtnBrowse_Click;
            this.Controls.Add(lblOutput);
            this.Controls.Add(txtOutputPath);
            this.Controls.Add(btnBrowse);

            // Additional Sites checkbox
            chkAdditionalSites = new CheckBox { Text = "Additional sites (3+)", Location = new System.Drawing.Point(20, 345), Size = new System.Drawing.Size(200, 25) };
            chkAdditionalSites.CheckedChanged += (s, e) => txtAdditionalSites.Enabled = chkAdditionalSites.Checked;
            this.Controls.Add(chkAdditionalSites);

            // Additional Sites TextBox
            txtAdditionalSites = new TextBox { Location = new System.Drawing.Point(220, 345), Size = new System.Drawing.Size(350, 25), PlaceholderText = "192.168.333.20,192.168.444.20", Enabled = false };
            this.Controls.Add(txtAdditionalSites);

            // Schedule Option
            chkSchedule = new CheckBox { Text = "Create scheduled task", Location = new System.Drawing.Point(20, 375), Size = new System.Drawing.Size(200, 25), Checked = true };
            chkSchedule.CheckedChanged += ChkSchedule_CheckedChanged;
            this.Controls.Add(chkSchedule);

            cmbScheduleFrequency = new ComboBox { Location = new System.Drawing.Point(220, 373), Size = new System.Drawing.Size(150, 25), DropDownStyle = ComboBoxStyle.DropDownList, Enabled = true };
            cmbScheduleFrequency.Items.AddRange(new object[] { "Daily", "Weekly", "Monthly" });
            cmbScheduleFrequency.SelectedIndex = 1; // Weekly default
            this.Controls.Add(cmbScheduleFrequency);

            // Lab mode checkbox (above progress bar)
            chkInsecure = new CheckBox { Text = "Lab mode (skip SSL verification)", Location = new System.Drawing.Point(20, 405), Size = new System.Drawing.Size(300, 25), ForeColor = System.Drawing.Color.Red };
            this.Controls.Add(chkInsecure);

            // Evaluate Cyber Resilience (LTR)
            chkUseLtr = new CheckBox { Text = "Evaluate Cyber Resilience (LTR)", Location = new System.Drawing.Point(20, 430), Size = new System.Drawing.Size(300, 25) };
            this.Controls.Add(chkUseLtr);

            // Progress Bar (now below checkboxes)
            progressBar = new ProgressBar { Location = new System.Drawing.Point(20, 460), Size = new System.Drawing.Size(560, 25), Style = ProgressBarStyle.Marquee, Visible = false };
            this.Controls.Add(progressBar);

            // Status Label
            lblStatus = new Label { Text = "Ready to run compliance scan", Location = new System.Drawing.Point(20, 490), Size = new System.Drawing.Size(560, 20), ForeColor = System.Drawing.Color.Gray };
            this.Controls.Add(lblStatus);

            // Output window
            rtbOutput = new RichTextBox { Location = new System.Drawing.Point(20, 515), Size = new System.Drawing.Size(560, 80), ReadOnly = true, BackColor = System.Drawing.Color.White, BorderStyle = BorderStyle.FixedSingle, Font = new System.Drawing.Font("Consolas", 8) };
            this.Controls.Add(rtbOutput);

            // Buttons
            btnRun = new Button { Text = "Run Now", Location = new System.Drawing.Point(250, 635), Size = new System.Drawing.Size(120, 40), BackColor = System.Drawing.Color.FromArgb(1, 169, 130), ForeColor = System.Drawing.Color.White, FlatStyle = FlatStyle.Flat };
            btnRun.Click += BtnRun_Click;
            this.Controls.Add(btnRun);

            btnSchedule = new Button { Text = "Schedule Task", Location = new System.Drawing.Point(380, 635), Size = new System.Drawing.Size(120, 40), BackColor = System.Drawing.Color.FromArgb(255, 184, 28), ForeColor = System.Drawing.Color.White, FlatStyle = FlatStyle.Flat, Enabled = true };
            btnSchedule.Click += BtnSchedule_Click;
            this.Controls.Add(btnSchedule);

            btnCancel = new Button { Text = "Close", Location = new System.Drawing.Point(510, 635), Size = new System.Drawing.Size(70, 40) };
            btnCancel.Click += (s, e) => this.Close();
            this.Controls.Add(btnCancel);

            // Help button
            btnHelp = new Button { Text = "Help", Location = new System.Drawing.Point(20, 635), Size = new System.Drawing.Size(80, 40) };
            btnHelp.Click += BtnHelp_Click;
            this.Controls.Add(btnHelp);
        }

        private void BtnBrowse_Click(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "Select output folder for compliance reports";
                dialog.SelectedPath = txtOutputPath.Text;
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    txtOutputPath.Text = dialog.SelectedPath;
                }
            }
        }

        private void ChkSchedule_CheckedChanged(object sender, EventArgs e)
        {
            cmbScheduleFrequency.Enabled = chkSchedule.Checked;
        }

        private void BtnRun_Click(object sender, EventArgs e)
        {
            if (!ValidateInputs())
                return;

            // Disable controls during execution
            SetControlsEnabled(false);
            progressBar.Visible = true;
            lblStatus.Text = "Running compliance scan...";
            lblStatus.ForeColor = System.Drawing.Color.Blue;

            // Run PowerShell script in background
            System.Threading.Tasks.Task.Run(() => RunComplianceScript());
        }
        private void BtnHelp_Click(object sender, EventArgs e)
        {
            try
            {
                string mailtoLink = "mailto:aaron.lastoff@hpe.com?subject=Zerto%20Compliance%20Tool&body=Please%20describe%20your%20issue%20or%20question%20here.";
                Process.Start(new ProcessStartInfo(mailtoLink) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Unable to open email client: {ex.Message}\n\nPlease contact aaron.lastoff@hpe.com with subject: Zerto Compliance Tool", "Help", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void BtnSchedule_Click(object sender, EventArgs e)
        {
            MessageBox.Show(
                "Task Scheduler integration requires administrator elevation and system configuration that may not be available in all environments.\n\n" +
                "For now, please use 'Run Now' to execute the compliance audit.\n\n" +
                "Alternatively, you can schedule the PowerShell script directly:\n" +
                "powershell -ExecutionPolicy Bypass -File Run-ComplianceAudit.ps1 [parameters]",
                "Schedule Task Not Available",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }

        private bool ValidateInputs()
        {
            if (string.IsNullOrWhiteSpace(txtZvmaHost.Text))
            {
                MessageBox.Show("Please enter the ZVMA host address.", "Validation Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtZvmaHost.Focus();
                return false;
            }

            if (string.IsNullOrWhiteSpace(txtUsername.Text))
            {
                MessageBox.Show("Please enter the username.", "Validation Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtUsername.Focus();
                return false;
            }

            if (string.IsNullOrWhiteSpace(txtPassword.Text))
            {
                MessageBox.Show("Please enter the password.", "Validation Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtPassword.Focus();
                return false;
            }

            if (string.IsNullOrWhiteSpace(txtOutputPath.Text))
            {
                MessageBox.Show("Please select an output folder.", "Validation Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                btnBrowse.Focus();
                return false;
            }

            return true;
        }

        private void RunComplianceScript()
        {
            try
            {
                // Find the PowerShell script - prioritize same directory as EXE (installed location)
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string scriptPath = Path.Combine(exeDir, "Run-ComplianceAudit.ps1");
                
                AppendOutput($"Looking for script in: {scriptPath}\n");
                
                if (!File.Exists(scriptPath))
                {
                    // Try parent directory (dev environment)
                    scriptPath = Path.GetFullPath(Path.Combine(exeDir, "..", "Run-ComplianceAudit.ps1"));
                    AppendOutput($"Not found. Trying: {scriptPath}\n");
                }
                
                if (!File.Exists(scriptPath))
                {
                    // Try two levels up (build output structure)
                    scriptPath = Path.GetFullPath(Path.Combine(exeDir, "..", "..", "Run-ComplianceAudit.ps1"));
                    AppendOutput($"Not found. Trying: {scriptPath}\n");
                }

                if (!File.Exists(scriptPath))
                {
                    UpdateStatus($"ERROR: Run-ComplianceAudit.ps1 not found!", System.Drawing.Color.Red);
                    AppendOutput($"\nScript not found in any expected location.\n");
                    AppendOutput($"Please ensure Run-ComplianceAudit.ps1 is in the same folder as the launcher EXE.\n");
                    AppendOutput($"Expected: {Path.Combine(exeDir, "Run-ComplianceAudit.ps1")}\n");
                    SetControlsEnabled(true);
                    return;
                }
                
                AppendOutput($"Found script: {scriptPath}\n\n");

                // Build PowerShell command
                StringBuilder psCommand = new StringBuilder();
                psCommand.Append($"& '{scriptPath}' ");
                psCommand.Append($"-ZVMAHost '{txtZvmaHost.Text}' ");
                psCommand.Append($"-Username '{txtUsername.Text}' ");
                psCommand.Append($"-Password '{txtPassword.Text}' ");
                psCommand.Append($"-OutRoot '{txtOutputPath.Text}' ");
                psCommand.Append($"-NonInteractive ");
                
                if (chkInsecure.Checked)
                {
                    psCommand.Append($"-Insecure ");
                }

                if (chkUseLtr.Checked)
                {
                    psCommand.Append($"-UseLTR ");
                }
                
                // Secondary site
                if (!string.IsNullOrWhiteSpace(txtPeerHosts.Text))
                {
                    string[] peerHosts = txtPeerHosts.Text.Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    psCommand.Append($"-PeerHosts @('{string.Join("','", peerHosts)}') ");
                }

                // Secondary credentials (only if different)
                if (chkDifferentSecondaryAuth.Checked && !string.IsNullOrWhiteSpace(txtSecondaryUsername.Text))
                {
                    psCommand.Append($"-SecondaryUsername '{txtSecondaryUsername.Text}' ");
                    psCommand.Append($"-SecondaryPassword '{txtSecondaryPassword.Text}' ");
                }

                // Additional sites (3+)
                if (chkAdditionalSites.Checked && !string.IsNullOrWhiteSpace(txtAdditionalSites.Text))
                {
                    string[] additionalSites = txtAdditionalSites.Text.Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    psCommand.Append($"-AdditionalSites @('{string.Join("','", additionalSites)}') ");
                }

                // Create process to run PowerShell
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-ExecutionPolicy Bypass -NoProfile -Command \"{psCommand}\"",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                using (Process process = new Process { StartInfo = psi })
                {
                    StringBuilder output = new StringBuilder();
                    StringBuilder errors = new StringBuilder();

                    process.OutputDataReceived += (s, e) =>
                    {
                        if (e.Data != null)
                        {
                            output.AppendLine(e.Data);
                            AppendOutput(e.Data + Environment.NewLine);
                        }
                    };
                    process.ErrorDataReceived += (s, e) =>
                    {
                        if (e.Data != null)
                        {
                            errors.AppendLine(e.Data);
                            AppendOutput(e.Data + Environment.NewLine);
                        }
                    };

                    process.Start();
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();

                    string outputText = output.ToString();
                    string errorText = errors.ToString();

                    // Check for success
                    if (process.ExitCode == 0 && !errorText.Contains("Fatal error"))
                    {
                        UpdateStatus("✓ Compliance scan completed successfully!", System.Drawing.Color.Green);
                        
                        // Find the generated report
                        string reportPath = FindLatestReport(txtOutputPath.Text);
                        if (!string.IsNullOrEmpty(reportPath))
                        {
                            this.Invoke((Action)(() =>
                            {
                                // Enhanced completion dialog
                                Form completionForm = new Form
                                {
                                    Text = "Compliance Scan Complete",
                                    Size = new System.Drawing.Size(500, 280),
                                    StartPosition = FormStartPosition.CenterParent,
                                    FormBorderStyle = FormBorderStyle.FixedDialog,
                                    MaximizeBox = false,
                                    MinimizeBox = false,
                                    BackColor = System.Drawing.Color.White
                                };

                                // Success icon (✓)
                                Label lblIcon = new Label
                                {
                                    Text = "✓",
                                    Font = new System.Drawing.Font("Segoe UI", 48, System.Drawing.FontStyle.Bold),
                                    ForeColor = System.Drawing.Color.FromArgb(1, 169, 130),
                                    Location = new System.Drawing.Point(210, 20),
                                    Size = new System.Drawing.Size(80, 80),
                                    TextAlign = System.Drawing.ContentAlignment.MiddleCenter
                                };
                                completionForm.Controls.Add(lblIcon);

                                // Success message
                                Label lblMessage = new Label
                                {
                                    Text = "Compliance Scan Completed Successfully!",
                                    Font = new System.Drawing.Font("Segoe UI", 14, System.Drawing.FontStyle.Bold),
                                    ForeColor = System.Drawing.Color.FromArgb(51, 51, 51),
                                    Location = new System.Drawing.Point(20, 110),
                                    Size = new System.Drawing.Size(460, 30),
                                    TextAlign = System.Drawing.ContentAlignment.MiddleCenter
                                };
                                completionForm.Controls.Add(lblMessage);

                                // Report path
                                Label lblPath = new Label
                                {
                                    Text = $"Report: {Path.GetFileName(Path.GetDirectoryName(reportPath))}",
                                    Font = new System.Drawing.Font("Segoe UI", 9),
                                    ForeColor = System.Drawing.Color.Gray,
                                    Location = new System.Drawing.Point(20, 145),
                                    Size = new System.Drawing.Size(460, 20),
                                    TextAlign = System.Drawing.ContentAlignment.MiddleCenter
                                };
                                completionForm.Controls.Add(lblPath);

                                // Open Report button (green)
                                Button btnOpenReport = new Button
                                {
                                    Text = "Open HTML Report",
                                    Location = new System.Drawing.Point(90, 180),
                                    Size = new System.Drawing.Size(150, 40),
                                    BackColor = System.Drawing.Color.FromArgb(1, 169, 130),
                                    ForeColor = System.Drawing.Color.White,
                                    FlatStyle = FlatStyle.Flat,
                                    Font = new System.Drawing.Font("Segoe UI", 10, System.Drawing.FontStyle.Bold),
                                    Cursor = System.Windows.Forms.Cursors.Hand
                                };
                                btnOpenReport.FlatAppearance.BorderSize = 0;
                                btnOpenReport.Click += (s, ev) =>
                                {
                                    try
                                    {
                                        Process.Start(new ProcessStartInfo(reportPath) { UseShellExecute = true });
                                        completionForm.Close();
                                    }
                                    catch (Exception ex)
                                    {
                                        MessageBox.Show($"Could not open report: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                                    }
                                };
                                completionForm.Controls.Add(btnOpenReport);

                                // Open Folder button (blue)
                                Button btnOpenFolder = new Button
                                {
                                    Text = "Open Folder",
                                    Location = new System.Drawing.Point(260, 180),
                                    Size = new System.Drawing.Size(150, 40),
                                    BackColor = System.Drawing.Color.FromArgb(0, 120, 212),
                                    ForeColor = System.Drawing.Color.White,
                                    FlatStyle = FlatStyle.Flat,
                                    Font = new System.Drawing.Font("Segoe UI", 10),
                                    Cursor = System.Windows.Forms.Cursors.Hand
                                };
                                btnOpenFolder.FlatAppearance.BorderSize = 0;
                                btnOpenFolder.Click += (s, ev) =>
                                {
                                    try
                                    {
                                        Process.Start(new ProcessStartInfo("explorer.exe", Path.GetDirectoryName(reportPath)) { UseShellExecute = true });
                                        completionForm.Close();
                                    }
                                    catch (Exception ex)
                                    {
                                        MessageBox.Show($"Could not open folder: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                                    }
                                };
                                completionForm.Controls.Add(btnOpenFolder);

                                completionForm.ShowDialog(this);
                            }));
                        }
                        else if (string.IsNullOrEmpty(reportPath))
                        {
                            this.Invoke((Action)(() =>
                            {
                                MessageBox.Show("Compliance scan completed, but Report.html was not found.\n\nCheck the output folder for other artifacts.", 
                                    "Completed", MessageBoxButtons.OK, MessageBoxIcon.Information);
                            }));
                        }
                    }
                    else
                    {
                        UpdateStatus($"✗ Error during scan", System.Drawing.Color.Red);
                        this.Invoke((Action)(() =>
                        {
                            MessageBox.Show($"Script execution failed. Check the output window and log files for details.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }));
                    }
                }
            }
            catch (Exception ex)
            {
                UpdateStatus($"Error: {ex.Message}", System.Drawing.Color.Red);
                this.Invoke((Action)(() =>
                {
                    MessageBox.Show($"Failed to run compliance script:\n\n{ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }));
            }
            finally
            {
                SetControlsEnabled(true);
                this.Invoke((Action)(() => progressBar.Visible = false));
                ClearOutput();
            }
        }

        private string FindLatestReport(string outputDir)
        {
            try
            {
                if (!Directory.Exists(outputDir))
                    return null;

                // Search for both new and legacy directory patterns
                var allDirs = Directory.GetDirectories(outputDir, "ComplianceAudit_*")
                    .Concat(Directory.GetDirectories(outputDir, "ZertoCompliance_*"))
                    .OrderByDescending(d => Directory.GetLastWriteTime(d))
                    .ToArray();

                if (allDirs.Length == 0)
                    return null;

                // Prefer most recently written directory
                foreach (var dir in allDirs)
                {
                    // Try multiple report filename patterns ordered by last write time
                    string[] reportPatterns = new[] { "Report*.html", "Report.html", "*.html" };
                    foreach (var pattern in reportPatterns)
                    {
                        var htmlFiles = Directory.GetFiles(dir, pattern)
                            .OrderByDescending(f => File.GetLastWriteTime(f))
                            .ToArray();
                        if (htmlFiles.Length > 0)
                        {
                            return htmlFiles[0];
                        }
                    }
                }

                return null;
            }
            catch (Exception)
            {
                return null;
            }
        }

        private void UpdateStatus(string message, System.Drawing.Color color)
        {
            if (lblStatus.InvokeRequired)
            {
                lblStatus.Invoke((Action)(() =>
                {
                    lblStatus.Text = message;
                    lblStatus.ForeColor = color;
                }));
            }
            else
            {
                lblStatus.Text = message;
                lblStatus.ForeColor = color;
            }
        }

        private void AppendOutput(string text)
        {
            if (rtbOutput.InvokeRequired)
            {
                rtbOutput.Invoke((Action)(() =>
                {
                    rtbOutput.SelectionStart = 0;
                    rtbOutput.SelectedText = text;
                    rtbOutput.SelectionStart = 0;
                    rtbOutput.ScrollToCaret();
                }));
            }
            else
            {
                rtbOutput.SelectionStart = 0;
                rtbOutput.SelectedText = text;
                rtbOutput.SelectionStart = 0;
                rtbOutput.ScrollToCaret();
            }
        }

        private void ClearOutput()
        {
            if (rtbOutput.InvokeRequired)
            {
                rtbOutput.Invoke((Action)(() => rtbOutput.Clear()));
            }
            else
            {
                rtbOutput.Clear();
            }
        }

        private void SetControlsEnabled(bool enabled)
        {
            if (this.InvokeRequired)
            {
                this.Invoke((Action)(() => SetControlsEnabled(enabled)));
                return;
            }

            txtZvmaHost.Enabled = enabled;
            txtUsername.Enabled = enabled;
            txtPassword.Enabled = enabled;
            txtPeerHosts.Enabled = enabled;
            btnBrowse.Enabled = enabled;
            btnRun.Enabled = enabled;
            chkSchedule.Enabled = enabled;
            cmbScheduleFrequency.Enabled = enabled && chkSchedule.Checked;
            btnSchedule.Enabled = enabled && chkSchedule.Checked;
            btnHelp.Enabled = true;
        }
    }
}
