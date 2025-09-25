# Dual Primaries Plugin for Left 4 Dead 2 (v1.5.8)

A SourceMod plugin that allows players to store and switch between two primary weapons with complete state preservation including ammo, attachments, and upgrades.

## Requirements

- **SourceMod**: 1.10 or higher
- **Game**: Left 4 Dead 2
- **Server**: Dedicated or Listen server

## Features

- **Dual Weapon Storage**: Store two primary weapons and switch between them instantly
- **Complete State Preservation**: Maintains ammo count, clip size, and weapon upgrades (laser, incendiary, explosive)
- **Automatic Storage**: Automatically stores your previous weapon when picking up a new one
- **Smart Auto-Switching**: Automatically switches to your other primary when current weapon is depleted
- **Special Weapon Support**: Full support for M60 and Grenade Launcher auto-switching
- **Manual Storage**: Manually store weapons using commands
- **Configurable Output**: Toggle debug mode and chat hints on/off
- **Key Binding Support**: Bind weapon switching to any key
- **Multiple Command Types**: Chat, console, and server commands available
- **Minimalist UI**: Clean, unobtrusive notifications
- **Text HUD Display**: Shows a simple text overlay with stored weapons and their ammo counts

## Video Demonstration

[![Watch the video](https://img.youtube.com/vi/VtSq4Bn-Kos/maxresdefault.jpg)](https://www.youtube.com/watch?v=VtSq4Bn-Kos)

## Installation

1. **Download**: Place `dual_primaries.smx` in your `addons/sourcemod/plugins/` folder
2. **Restart**: Restart your server or use `sm plugins load dual_primaries`
3. **Configure**: Edit the auto-generated config file at `cfg/sourcemod/dualprimary.cfg`

## Commands

### Player Commands
- `!switchprimary` or `switchprimary` - Switch between stored weapons
- `!storeprimary` or `storeprimary` - Store current primary weapon
- `!dualinfo` or `dualinfo` - Show current plugin status and settings
- `!dualhelp` or `dualhelp` - Show available commands and binding help

### Admin Commands (Requires ADMFLAG_ROOT)
- `!primarystatus` - Show status of both weapon slots
- `sm_primarystatus` - Show weapon status in console
- `sm_primarystatus_server <client_id>` - Show status for specific client
- `sm_switchprimary_server <client_id>` - Switch weapons for specific client
- `sm_storeprimary_server <client_id>` - Store weapon for specific client

### Key Binding
```
bind "KEY" "sm_switchprimary"   // Bind a key to switch weapons
bind "KEY" "sm_storeprimary"    // Bind a key to store current weapon
```

## Key Binding

### Recommended Binds

#### For All Game Modes:
```
bind "q" "sm_switchprimary"      // Switch between weapons
bind "v" "sm_storeprimary"       // Store current weapon
bind "b" "sm_dualhelp"           // Show help
```

### Console Commands:
- `sm_switchprimary` - Switch between stored weapons
- `sm_storeprimary` - Store current weapon
- `sm_dualinfo` - Show plugin status
- `sm_dualhelp` - Show command help

**Tip**: Use `sm_` prefix for reliable command execution in all contexts.

## Configuration

Edit the auto-generated config file at `cfg/sourcemod/plugin.dual_primaries.cfg` to customize these settings:

### ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `sm_dualprimary_debug` | `0` | Debug output level (0=disabled, 1-2=debug levels) |
| `sm_dualprimary_chathints` | `0` | Show chat notifications (0=disabled, 1=enabled) |
| `sm_dualprimary_allowduplicates` | `0` | Allow duplicate primary weapons (0=disabled, 1=enabled) |
| `sm_dualprimary_showwelcome` | `1` | Show welcome message on load (0=disabled, 1=enabled) |
| `sm_dualprimary_cooldown` | `1.0` | Cooldown between weapon switches (in seconds) |
| `sm_dualprimary_showhud` | `1` | Show text HUD overlay with stored weapons (0=disabled, 1=enabled) |
| `sm_dualprimary_autoswitch` | `1` | Auto-switch to other primary when ammo is depleted (0=disabled, 1=enabled) |
| `sm_dualprimary_autoswitch_special` | `1` | Auto-switch special weapons when ammo is depleted and dropped (M60/Grenade Launcher) (0=disabled, 1=enabled) |

### Configuration Examples

**Clean Gameplay (Recommended)**:
```
sm_dualprimary_debug 0     // No debug spam
sm_dualprimary_chathints 1     // Show weapon pickup messages
sm_dualprimary_allowduplicates 0  // Prevent duplicate weapons
sm_dualprimary_showhud 1      // Show text HUD with stored weapons
sm_dualprimary_autoswitch 1   // Auto-switch when ammo is depleted
sm_dualprimary_autoswitch_special 1  // Auto-switch for M60/Grenade Launcher
```

## How It Works

### Automatic Storage
1. **First Weapon**: Gets stored in Slot 1
2. **Second Weapon**: Previous weapon moves to Slot 2, new weapon goes to Slot 1
3. **Third Weapon**: Only replaces Slot 1 (Slot 2 stays protected)

### Duplicate Weapon Restriction
When `sm_dualprimary_allowduplicates` is set to `0` (recommended):
- Players cannot have the same weapon in both slots
- Attempting to pick up a duplicate weapon is blocked
- Switching to a weapon that would create a duplicate clears the second slot
- Players receive a message when duplicate weapons are blocked

### Manual Storage
- Use `!storeprimary` to manually store your current weapon in Slot 2
- Overwrites any existing weapon in Slot 2

### Weapon Switching
- Use `!switchprimary` to swap between Slot 1 and Slot 2
- Preserves exact weapon state including:
  - Current clip ammo
  - Reserve ammo count
  - Laser sight attachment
  - Incendiary/Explosive upgrades

## Supported Weapons

The plugin works with all L4D2 primary weapons:

### Assault Rifles
- AK-47 (`weapon_rifle_ak47`)
- M16A2 (`weapon_rifle`)
- SCAR-L (`weapon_rifle_desert`)
- M60 (`weapon_m60`)

### Submachine Guns
- Uzi (`weapon_smg`)
- Silenced SMG (`weapon_smg_silenced`)
- MP5 (`weapon_smg_mp5`)

### Shotguns
- Pump Shotgun (`weapon_pumpshotgun`)
- Chrome Shotgun (`weapon_shotgun_chrome`)
- Auto Shotgun (`weapon_autoshotgun`)
- SPAS-12 (`weapon_shotgun_spas`)

### Sniper Rifles
- Hunting Rifle (`weapon_hunting_rifle`)
- Military Sniper (`weapon_sniper_military`)
- AWP (`weapon_sniper_awp`)
- Scout (`weapon_sniper_scout`)

## Usage Examples

### Basic Usage
1. Pick up an assault rifle → Stored in Slot 1
2. Pick up a shotgun → Rifle moves to Slot 2, shotgun in Slot 1
3. Press your bind key → Switch back to rifle
4. Press bind again → Switch back to shotgun

### Manual Storage
1. Have a weapon you want to keep
2. Type `!storeprimary` or press your store bind
3. Pick up a different weapon
4. Use `!switchprimary` to switch between them

### Status Check
- Type `!primarystatus` to see:
  - What weapons are stored in each slot
  - Current ammo counts
  - Active upgrades (L=Laser, I=Incendiary, E=Explosive)

## Troubleshooting

### Commands Not Working
- Try server commands: `sm_switchprimary_server <your_client_id>`
- Check if plugin is loaded: `sm plugins list`
- Reload plugin: `sm plugins reload dual_primaries`

### No Automatic Storage
- Check if you're picking up primary weapons (not pistols/melee)

### Duplicate Weapons Not Blocked
- Verify `sm_dualprimary_allowduplicates` is set to `0`
- Check for any conflicting plugins that might modify weapon behavior
- Ensure you're using the latest version of the plugin
- Enable debug mode: `sm_dualprimary_debug 1`
- Check console for error messages

### Key Binds Not Working
- Use server commands in binds: `bind "q" "sm_switchprimary_server 1"`
- Replace `1` with your actual client ID if needed
- Try alternative bind format: `bind "q" "switchprimary"`

### Finding Your Client ID
- Type `status` in console to see client IDs
- Usually `1` for listen server host
- Use `!primarystatus` to test if commands work first

## Version History

### v1.0.0
- Initial release
- Basic weapon switching functionality
- Automatic and manual storage
- Complete state preservation
- Configurable output modes
- Key binding support

## Support

If you encounter issues:
1. Enable debug mode: `sm_dualprimary_debug 1`
2. Check server console for errors
3. Verify plugin is loaded: `sm plugins list`
4. Test with manual commands before using binds

## License

This plugin is provided as-is for Left 4 Dead 2 servers. Feel free to modify and redistribute.
