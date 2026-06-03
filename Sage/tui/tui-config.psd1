# tui/tui-config.psd1
# TUI workspace config — vanilla/default settings shipped with the module.
#
# This file is read-only as far as the TUI is concerned.  On the first time a
# student modifies a setting (domain name, targets, theme, output dir), the TUI
# copies this file to data/config/tui-config-personal.psd1 and writes all changes there.
# Subsequent TUI launches use data/config/tui-config-personal.psd1 automatically.
#
# Students should NOT edit this file directly.  Change settings through the TUI
# Settings screen or by editing data/config/tui-config-personal.psd1.
# If LAN IPs are unreachable, the TUI prompts for a public hostname.

@{
    # ── Exam source ───────────────────────────────────────────────────────────────
    # Path to the Lab 1, 2 (Windows Server setup, DNS) + Lab 5-7 (Group Policy, DHCP, AD Sites) + Apache + Nginx exam definition.
    ExamDefinitionPath = '../data/werkcolleges/ServerOS-proefexamen.psd1'

    # ── Target display order ─────────────────────────────────────────────────────
    # Explicit order in which targets are presented in the TUI selector.
    # Must match the keys defined in the Targets hashtable below.
    TargetOrder        = @('DC1', 'Client', 'Linux')

    # ── Target connection overrides ───────────────────────────────────────────────
    # These override the HostName for each target.
    # Primary = LAN IP (tried first); Fallback = public DNS (prompted if needed).
    Targets            = @{
        DC1    = @{
            PrimaryHostName  = '192.168.1.3'
            FallbackHostName = ''
            Port             = 22
            FallbackPort     = 30022
        }
        Client = @{
            PrimaryHostName  = '192.168.1.5'
            FallbackHostName = ''
            Port             = 22
            FallbackPort     = 50022
        }
        Linux  = @{
            PrimaryHostName  = '192.168.1.2'
            FallbackHostName = ''
            Port             = 22
            FallbackPort     = 20022
        }
    }

    # ── Remembered TUI preferences ────────────────────────────────────────────────
    # These values are updated by the TUI so future runs can reuse choices.
    Remembered         = @{
        DomainName            = ''
        SelectedTargets       = @('DC1', 'Client', 'Linux')
        SelectedCategories    = ''
        PreferFallbackTargets = ''
        Theme                 = '13. Nord Ice'
        OutputDir             = '../data/output'
    }
}
