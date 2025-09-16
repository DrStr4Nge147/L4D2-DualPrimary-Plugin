/**
 * Dual Primaries (L4D2 version)
 * Fixed to properly save weapon states including ammo and attachments
 */

#include <sourcemod>
#include <sdktools>

#define MAX_PLAYERS 33

// Weapon state structure
enum struct WeaponState
{
    char classname[64];
    int clip;
    int ammo;
    int upgrades;
    bool hasLaser;
    bool hasIncendiary;
    bool hasExplosive;
    bool isValid;
}

WeaponState g_PrimarySlot1[MAX_PLAYERS];
WeaponState g_PrimarySlot2[MAX_PLAYERS];

// Global variables for tracking
char g_LastWeapon[MAX_PLAYERS][64];
int g_LastAmmo[MAX_PLAYERS];
bool g_IsWeaponSwitching[MAX_PLAYERS];

// ConVars for toggles
ConVar g_cvDebugMode;
ConVar g_cvChatHints;

public void OnPluginStart()
{
    // Create ConVars for toggles
    g_cvDebugMode = CreateConVar("sm_dualprimary_debug", "0", "Enable debug output (0=disabled, 1=enabled)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvChatHints = CreateConVar("sm_dualprimary_hints", "1", "Enable chat hints for weapon pickup (0=disabled, 1=enabled)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    
    RegConsoleCmd("sm_switchprimary", Cmd_SwitchPrimary, "Switch between two primaries");
    RegConsoleCmd("sm_storeprimary", Cmd_StorePrimary, "Manually store current primary weapon");
    RegConsoleCmd("sm_primarystatus", Cmd_PrimaryStatus, "Show stored primary weapons");
    
    // Add client command for binding (without sm_ prefix)
    RegConsoleCmd("switchprimary", Cmd_SwitchPrimary, "Switch between two primaries (bindable)");
    RegConsoleCmd("storeprimary", Cmd_StorePrimary, "Manually store current primary weapon (bindable)");
    RegConsoleCmd("primarystatus", Cmd_PrimaryStatus, "Show stored primary weapons (bindable)");
    
    // Add server commands for console use
    RegServerCmd("sm_switchprimary_server", Cmd_SwitchPrimary_Server, "Switch primary weapons from server console");
    RegServerCmd("sm_storeprimary_server", Cmd_StorePrimary_Server, "Store primary weapon from server console");
    RegServerCmd("sm_primarystatus_server", Cmd_PrimaryStatus_Server, "Show primary status from server console");
    
    HookEvent("weapon_drop", Event_WeaponDrop);
    HookEvent("item_pickup", Event_ItemPickup);
    HookEvent("weapon_pickup", Event_WeaponPickup);
    
    // Create a timer to check for ammo changes since ammo_pickup event doesn't exist in L4D2
    CreateTimer(0.5, Timer_CheckAmmoChanges, _, TIMER_REPEAT);
    
    // Create a timer to periodically check for weapon changes
    CreateTimer(1.0, Timer_CheckWeaponChanges, _, TIMER_REPEAT);
    
    // Auto-generate config file
    AutoExecConfig(true, "dualprimary");
}

public void OnClientPutInServer(int client)
{
    ClearWeaponState(g_PrimarySlot1[client]);
    ClearWeaponState(g_PrimarySlot2[client]);
    g_LastAmmo[client] = -1;
    g_IsWeaponSwitching[client] = false;
}

void ClearWeaponState(WeaponState weapon)
{
    weapon.classname[0] = '\0';
    weapon.clip = 0;
    weapon.ammo = 0;
    weapon.upgrades = 0;
    weapon.hasLaser = false;
    weapon.hasIncendiary = false;
    weapon.hasExplosive = false;
    weapon.isValid = false;
}

void CopyWeaponState(WeaponState source, WeaponState dest)
{
    strcopy(dest.classname, sizeof(dest.classname), source.classname);
    dest.clip = source.clip;
    dest.ammo = source.ammo;
    dest.upgrades = source.upgrades;
    dest.hasLaser = source.hasLaser;
    dest.hasIncendiary = source.hasIncendiary;
    dest.hasExplosive = source.hasExplosive;
    dest.isValid = source.isValid;
}

void SaveWeaponState(int weaponEntity, WeaponState weapon)
{
    if (weaponEntity <= 0 || !IsValidEntity(weaponEntity))
    {
        ClearWeaponState(weapon);
        return;
    }
    
    int owner = GetEntPropEnt(weaponEntity, Prop_Send, "m_hOwnerEntity");
    if (owner <= 0 || owner > MaxClients)
    {
        ClearWeaponState(weapon);
        return;
    }
    
    GetEntityClassname(weaponEntity, weapon.classname, sizeof(weapon.classname));
    weapon.clip = GetEntProp(weaponEntity, Prop_Send, "m_iClip1");
    
    // Get reserve ammo from the player, not the weapon
    int ammoType = GetEntProp(weaponEntity, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType >= 0)
    {
        weapon.ammo = GetEntProp(owner, Prop_Send, "m_iAmmo", _, ammoType);
    }
    else
    {
        weapon.ammo = 0;
    }
    
    weapon.upgrades = GetEntProp(weaponEntity, Prop_Send, "m_upgradeBitVec");
    weapon.hasLaser = (weapon.upgrades & 2) ? true : false;
    weapon.hasIncendiary = (weapon.upgrades & 4) ? true : false;
    weapon.hasExplosive = (weapon.upgrades & 8) ? true : false;
    weapon.isValid = true;
}

int RestoreWeaponState(int client, WeaponState weapon)
{
    if (!weapon.isValid || weapon.classname[0] == '\0')
        return -1;
    
    int newWeapon = GivePlayerItem(client, weapon.classname);
    if (newWeapon > 0 && IsValidEntity(newWeapon))
    {
        SetEntProp(newWeapon, Prop_Send, "m_iClip1", weapon.clip);
        SetEntProp(newWeapon, Prop_Send, "m_upgradeBitVec", weapon.upgrades);
        
        // Set ammo in reserve
        int ammoType = GetEntProp(newWeapon, Prop_Send, "m_iPrimaryAmmoType");
        if (ammoType >= 0)
        {
            SetEntProp(client, Prop_Send, "m_iAmmo", weapon.ammo, _, ammoType);
        }
    }
    
    return newWeapon;
}

// ----------------------
// ITEM PICKUP
// ----------------------
public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    char item[64];
    event.GetString("item", item, sizeof(item));
    
    if (g_cvDebugMode.BoolValue)
        PrintToChat(client, "[DEBUG] Item pickup detected: %s", item);

    if (IsPrimaryWeapon(item))
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Primary weapon pickup detected: %s", item);
        
        // Use a timer to handle weapon storage after pickup is complete
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteString(item);
        CreateTimer(0.1, Timer_HandleWeaponPickup, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
}

// ----------------------
// WEAPON PICKUP
// ----------------------
public void Event_WeaponPickup(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    if (g_cvDebugMode.BoolValue)
        PrintToChat(client, "[DEBUG] Weapon pickup detected: %s", weapon);

    if (IsPrimaryWeapon(weapon))
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Primary weapon pickup detected: %s", weapon);
        
        // Use a timer to handle weapon storage after pickup is complete
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteString(weapon);
        CreateTimer(0.1, Timer_HandleWeaponPickup, pack, TIMER_FLAG_NO_MAPCHANGE);
    }
}

// ----------------------
// PERIODIC WEAPON CHECK
// ----------------------

public Action Timer_CheckWeaponChanges(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
            continue;
            
        int weapon = GetPlayerWeaponSlot(client, 0);
        if (weapon <= 0 || !IsValidEntity(weapon))
            continue;
            
        char currentWeapon[64];
        GetEntityClassname(weapon, currentWeapon, sizeof(currentWeapon));
        
        if (!IsPrimaryWeapon(currentWeapon))
            continue;
            
        // Check if weapon changed
        if (!StrEqual(g_LastWeapon[client], currentWeapon, false))
        {
            if (g_LastWeapon[client][0] != '\0') // Had a previous weapon
            {
                if (g_cvDebugMode.BoolValue)
                    PrintToChat(client, "[DEBUG] Weapon change detected: %s -> %s", g_LastWeapon[client], currentWeapon);
                
                // Handle weapon change
                DataPack pack = new DataPack();
                pack.WriteCell(GetClientUserId(client));
                pack.WriteString(currentWeapon);
                CreateTimer(0.1, Timer_HandleWeaponPickup, pack, TIMER_FLAG_NO_MAPCHANGE);
            }
            
            strcopy(g_LastWeapon[client], sizeof(g_LastWeapon[]), currentWeapon);
        }
    }
    
    return Plugin_Continue;
}

public Action Timer_CheckAmmoChanges(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client))
            continue;
            
        int weapon = GetPlayerWeaponSlot(client, 0);
        if (weapon <= 0 || !IsValidEntity(weapon))
            continue;
            
        char currentWeapon[64];
        GetEntityClassname(weapon, currentWeapon, sizeof(currentWeapon));
        
        if (!IsPrimaryWeapon(currentWeapon))
            continue;
            
        // Get current ammo
        int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
        if (ammoType < 0) continue;
        
        int currentAmmo = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
        
        // Debug current ammo tracking
        if (g_cvDebugMode.BoolValue && g_LastAmmo[client] != currentAmmo)
            PrintToChat(client, "[DEBUG] Ammo change: %d -> %d for %s (switching: %s)", g_LastAmmo[client], currentAmmo, currentWeapon, g_IsWeaponSwitching[client] ? "yes" : "no");
        
        // Check if ammo increased (indicating pickup) but not during weapon switching
        if (g_LastAmmo[client] != -1 && currentAmmo > g_LastAmmo[client] && !g_IsWeaponSwitching[client])
        {
            if (g_cvDebugMode.BoolValue)
                PrintToChat(client, "[DEBUG] Ammo increase detected: %d -> %d (not switching)", g_LastAmmo[client], currentAmmo);
            
            // Replenish ammo for both stored primary weapons
            ReplenishBothPrimaryWeapons(client);
        }
        else if (g_IsWeaponSwitching[client] && g_cvDebugMode.BoolValue)
        {
            PrintToChat(client, "[DEBUG] Ammo change ignored during weapon switching");
        }
        
        g_LastAmmo[client] = currentAmmo;
    }
    
    return Plugin_Continue;
}

public Action Timer_HandleWeaponPickup(Handle timer, DataPack pack)
{
    pack.Reset();
    int userid = pack.ReadCell();
    char newWeaponName[64];
    pack.ReadString(newWeaponName, sizeof(newWeaponName));
    delete pack;
    
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;
    
    int currentWeapon = GetPlayerWeaponSlot(client, 0);
    if (currentWeapon <= 0 || !IsValidEntity(currentWeapon))
        return Plugin_Stop;
    
    char currentClassname[64];
    GetEntityClassname(currentWeapon, currentClassname, sizeof(currentClassname));
    
    // If we had a previous weapon stored in slot 1 and it's different from the new weapon
    if (g_PrimarySlot1[client].isValid && 
        !StrEqual(g_PrimarySlot1[client].classname, currentClassname, false))
    {
        // Only store the old weapon in slot 2 if slot 2 is empty
        if (!g_PrimarySlot2[client].isValid)
        {
            // Copy the old weapon from slot 1 to slot 2
            CopyWeaponState(g_PrimarySlot1[client], g_PrimarySlot2[client]);
            if (g_cvChatHints.BoolValue)
                PrintToChat(client, "[DualPrimaries] Auto-stored %s in slot 2.", g_PrimarySlot2[client].classname);
        }
    }
    
    // Save the new weapon in slot 1
    SaveWeaponState(currentWeapon, g_PrimarySlot1[client]);
    if (g_cvChatHints.BoolValue)
        PrintToChat(client, "[DualPrimaries] Equipped %s in slot 1.", currentClassname);
    
    return Plugin_Stop;
}

// ----------------------
// DROP EVENT
// ----------------------
public void Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    int weapon = event.GetInt("propid");
    if (weapon <= 0) return;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));

    if (IsPrimaryWeapon(classname))
    {
        // Only store in slot 2 if we don't already have a weapon stored there
        // and this weapon is different from what's currently in slot 1
        if (!g_PrimarySlot2[client].isValid && 
            g_PrimarySlot1[client].isValid && 
            !StrEqual(classname, g_PrimarySlot1[client].classname, false))
        {
            SaveWeaponState(weapon, g_PrimarySlot2[client]);
            PrintToChat(client, "[DualPrimaries] Stored %s in slot 2.", classname);
        }
    }
}

// ----------------------
// SWITCH COMMAND
// ----------------------
public Action Cmd_SwitchPrimary(int client, int args)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Handled;

    // Debug output
    if (g_cvDebugMode.BoolValue)
        PrintToChat(client, "[DEBUG] Slot2 Valid: %s, Classname: '%s'", 
            g_PrimarySlot2[client].isValid ? "Yes" : "No", 
            g_PrimarySlot2[client].classname);

    if (!g_PrimarySlot2[client].isValid || g_PrimarySlot2[client].classname[0] == '\0')
    {
        if (g_cvChatHints.BoolValue)
        {
            PrintToChat(client, "[DualPrimaries] No other weapon stored to switch to.");
            PrintToChat(client, "[DualPrimaries] Try using !storeprimary first to manually store a weapon.");
        }
        return Plugin_Handled;
    }

    // Mark that we're switching weapons to prevent ammo replenishment
    g_IsWeaponSwitching[client] = true;
    
    // Save current weapon state
    int currentWeapon = GetPlayerWeaponSlot(client, 0);
    WeaponState tempState;
    if (currentWeapon > 0)
    {
        SaveWeaponState(currentWeapon, tempState);
        RemovePlayerItem(client, currentWeapon);
        AcceptEntityInput(currentWeapon, "Kill"); // Properly remove the weapon entity
    }
    else
    {
        ClearWeaponState(tempState);
    }

    // Restore the stored weapon with its state
    int restoredWeapon = RestoreWeaponState(client, g_PrimarySlot2[client]);
    if (restoredWeapon > 0)
    {
        // Swap the weapon states using copy function
        WeaponState slot2Backup;
        CopyWeaponState(g_PrimarySlot2[client], slot2Backup);
        CopyWeaponState(tempState, g_PrimarySlot2[client]);
        CopyWeaponState(slot2Backup, g_PrimarySlot1[client]);

        if (g_cvChatHints.BoolValue)
            PrintToChat(client, "[DualPrimaries] Switched to %s (Clip: %d, Upgrades: %s%s%s).", 
                g_PrimarySlot1[client].classname,
                g_PrimarySlot1[client].clip,
                g_PrimarySlot1[client].hasLaser ? "L" : "",
                g_PrimarySlot1[client].hasIncendiary ? "I" : "",
                g_PrimarySlot1[client].hasExplosive ? "E" : "");
    }
    else
    {
        if (g_cvChatHints.BoolValue)
            PrintToChat(client, "[DualPrimaries] Failed to restore weapon state.");
    }

    // Clear the switching flag after a short delay to allow weapon switch to complete
    CreateTimer(1.0, Timer_ClearSwitchingFlag, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Handled;
}

// ----------------------
// STORE COMMAND
// ----------------------
public Action Cmd_StorePrimary(int client, int args)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Handled;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (weapon <= 0 || !IsValidEntity(weapon))
    {
        if (g_cvChatHints.BoolValue)
            PrintToChat(client, "[DualPrimaries] No primary weapon to store.");
        return Plugin_Handled;
    }

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    
    if (!IsPrimaryWeapon(classname))
    {
        if (g_cvChatHints.BoolValue)
            PrintToChat(client, "[DualPrimaries] Current weapon is not a primary weapon.");
        return Plugin_Handled;
    }

    SaveWeaponState(weapon, g_PrimarySlot2[client]);
    if (g_cvChatHints.BoolValue)
        PrintToChat(client, "[DualPrimaries] Manually stored %s in slot 2.", classname);
    
    return Plugin_Handled;
}

// ----------------------
// STATUS COMMAND
// ----------------------
public Action Cmd_PrimaryStatus(int client, int args)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return Plugin_Handled;

    PrintToChat(client, "[DualPrimaries] === Weapon Status ===");
    
    if (g_PrimarySlot1[client].isValid)
    {
        PrintToChat(client, "[DualPrimaries] Slot 1: %s (Clip: %d, Ammo: %d, Upgrades: %s%s%s)", 
            g_PrimarySlot1[client].classname,
            g_PrimarySlot1[client].clip,
            g_PrimarySlot1[client].ammo,
            g_PrimarySlot1[client].hasLaser ? "L" : "",
            g_PrimarySlot1[client].hasIncendiary ? "I" : "",
            g_PrimarySlot1[client].hasExplosive ? "E" : "");
    }
    else
    {
        PrintToChat(client, "[DualPrimaries] Slot 1: Empty");
    }
    
    if (g_PrimarySlot2[client].isValid)
    {
        PrintToChat(client, "[DualPrimaries] Slot 2: %s (Clip: %d, Ammo: %d, Upgrades: %s%s%s)", 
            g_PrimarySlot2[client].classname,
            g_PrimarySlot2[client].clip,
            g_PrimarySlot2[client].ammo,
            g_PrimarySlot2[client].hasLaser ? "L" : "",
            g_PrimarySlot2[client].hasIncendiary ? "I" : "",
            g_PrimarySlot2[client].hasExplosive ? "E" : "");
    }
    else
    {
        PrintToChat(client, "[DualPrimaries] Slot 2: Empty");
    }
    
    return Plugin_Handled;
}

// ----------------------
// SERVER COMMANDS
// ----------------------
public Action Cmd_SwitchPrimary_Server(int args)
{
    if (args < 1)
    {
        PrintToServer("[DualPrimaries] Usage: sm_switchprimary_server <client_id>");
        return Plugin_Handled;
    }
    
    char arg[32];
    GetCmdArg(1, arg, sizeof(arg));
    int client = StringToInt(arg);
    
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        PrintToServer("[DualPrimaries] Invalid client ID: %d", client);
        return Plugin_Handled;
    }
    
    return Cmd_SwitchPrimary(client, 0);
}

public Action Cmd_StorePrimary_Server(int args)
{
    if (args < 1)
    {
        PrintToServer("[DualPrimaries] Usage: sm_storeprimary_server <client_id>");
        return Plugin_Handled;
    }
    
    char arg[32];
    GetCmdArg(1, arg, sizeof(arg));
    int client = StringToInt(arg);
    
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        PrintToServer("[DualPrimaries] Invalid client ID: %d", client);
        return Plugin_Handled;
    }
    
    return Cmd_StorePrimary(client, 0);
}

public Action Cmd_PrimaryStatus_Server(int args)
{
    if (args < 1)
    {
        PrintToServer("[DualPrimaries] Usage: sm_primarystatus_server <client_id>");
        return Plugin_Handled;
    }
    
    char arg[32];
    GetCmdArg(1, arg, sizeof(arg));
    int client = StringToInt(arg);
    
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        PrintToServer("[DualPrimaries] Invalid client ID: %d", client);
        return Plugin_Handled;
    }
    
    return Cmd_PrimaryStatus(client, 0);
}

// ----------------------
// AMMO REPLENISHMENT
// ----------------------

void ReplenishBothPrimaryWeapons(int client)
{
    int currentWeapon = GetPlayerWeaponSlot(client, 0);
    if (currentWeapon <= 0 || !IsValidEntity(currentWeapon)) 
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] No valid current weapon");
        return;
    }
    
    char currentClassname[64];
    GetEntityClassname(currentWeapon, currentClassname, sizeof(currentClassname));
    
    if (!IsPrimaryWeapon(currentClassname)) 
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Current weapon %s is not primary", currentClassname);
        return;
    }
    
    // Get the current weapon's ammo type and current ammo amount
    int currentAmmoType = GetEntProp(currentWeapon, Prop_Send, "m_iPrimaryAmmoType");
    if (currentAmmoType < 0) 
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Invalid ammo type: %d", currentAmmoType);
        return;
    }
    
    int currentAmmo = GetEntProp(client, Prop_Send, "m_iAmmo", _, currentAmmoType);
    
    if (g_cvDebugMode.BoolValue)
        PrintToChat(client, "[DEBUG] Current weapon: %s, AmmoType: %d, Ammo: %d", currentClassname, currentAmmoType, currentAmmo);
    
    bool slot1Updated = false, slot2Updated = false;
    
    // Update stored weapon states with the new ammo amount
    if (g_PrimarySlot1[client].isValid)
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Slot1: %s, replenishing ammo", g_PrimarySlot1[client].classname);
        
        // Get the appropriate ammo amount for slot 1 weapon's ammo type
        int slot1AmmoType = GetWeaponAmmoType(g_PrimarySlot1[client].classname);
        int slot1Ammo = (slot1AmmoType == currentAmmoType) ? currentAmmo : GetEntProp(client, Prop_Send, "m_iAmmo", _, slot1AmmoType);
        
        // If slot1 uses different ammo type, set it to max ammo for that type
        if (slot1AmmoType != currentAmmoType)
        {
            slot1Ammo = GetMaxAmmoForWeapon(g_PrimarySlot1[client].classname);
        }
        else
        {
            slot1Ammo = currentAmmo;
        }
        
        g_PrimarySlot1[client].ammo = slot1Ammo;
        slot1Updated = true;
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Updated slot 1 (%s) ammo to %d", g_PrimarySlot1[client].classname, slot1Ammo);
    }
    else if (g_cvDebugMode.BoolValue)
    {
        PrintToChat(client, "[DEBUG] Slot1 is empty");
    }
    
    if (g_PrimarySlot2[client].isValid)
    {
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Slot2: %s, replenishing ammo", g_PrimarySlot2[client].classname);
        
        // Get the appropriate ammo amount for slot 2 weapon's ammo type
        int slot2AmmoType = GetWeaponAmmoType(g_PrimarySlot2[client].classname);
        int slot2Ammo = (slot2AmmoType == currentAmmoType) ? currentAmmo : GetEntProp(client, Prop_Send, "m_iAmmo", _, slot2AmmoType);
        
        // If slot2 uses different ammo type, set it to max ammo for that type
        if (slot2AmmoType != currentAmmoType)
        {
            slot2Ammo = GetMaxAmmoForWeapon(g_PrimarySlot2[client].classname);
        }
        else
        {
            slot2Ammo = currentAmmo;
        }
        
        g_PrimarySlot2[client].ammo = slot2Ammo;
        slot2Updated = true;
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Updated slot 2 (%s) ammo to %d", g_PrimarySlot2[client].classname, slot2Ammo);
    }
    else if (g_cvDebugMode.BoolValue)
    {
        PrintToChat(client, "[DEBUG] Slot2 is empty");
    }
    
    if (g_cvChatHints.BoolValue && (slot1Updated || slot2Updated))
        PrintToChat(client, "[DualPrimaries] Ammo replenished for %s%s%s.", 
            slot1Updated ? "slot 1" : "",
            (slot1Updated && slot2Updated) ? " and " : "",
            slot2Updated ? "slot 2" : "");
}

int GetWeaponAmmoType(const char[] weaponClassname)
{
    // Return the ammo type for a given weapon
    if (StrContains(weaponClassname, "rifle", false) != -1 ||
        StrEqual(weaponClassname, "weapon_rifle", false) ||
        StrEqual(weaponClassname, "weapon_rifle_ak47", false) ||
        StrEqual(weaponClassname, "weapon_rifle_desert", false) ||
        StrEqual(weaponClassname, "weapon_rifle_sg552", false) ||
        StrEqual(weaponClassname, "weapon_m60", false))
    {
        return 3; // Rifle ammo
    }
    else if (StrContains(weaponClassname, "smg", false) != -1 ||
             StrEqual(weaponClassname, "weapon_smg", false) ||
             StrEqual(weaponClassname, "weapon_smg_silenced", false) ||
             StrEqual(weaponClassname, "weapon_smg_mp5", false))
    {
        return 5; // SMG ammo
    }
    else if (StrContains(weaponClassname, "shotgun", false) != -1 ||
             StrEqual(weaponClassname, "weapon_shotgun_chrome", false) ||
             StrEqual(weaponClassname, "weapon_shotgun_spas", false) ||
             StrEqual(weaponClassname, "weapon_autoshotgun", false) ||
             StrEqual(weaponClassname, "weapon_pumpshotgun", false))
    {
        return 7; // Shotgun ammo
    }
    else if (StrContains(weaponClassname, "sniper", false) != -1 ||
             StrEqual(weaponClassname, "weapon_sniper_military", false) ||
             StrEqual(weaponClassname, "weapon_hunting_rifle", false))
    {
        return 9; // Sniper ammo
    }
    
    return -1; // Unknown weapon
}

int GetMaxAmmoForWeapon(const char[] weaponClassname)
{
    // Return max ammo for different weapon types
    if (StrContains(weaponClassname, "rifle", false) != -1 ||
        StrEqual(weaponClassname, "weapon_rifle", false) ||
        StrEqual(weaponClassname, "weapon_rifle_ak47", false) ||
        StrEqual(weaponClassname, "weapon_rifle_desert", false) ||
        StrEqual(weaponClassname, "weapon_rifle_sg552", false))
    {
        return 360; // Rifle max ammo
    }
    else if (StrEqual(weaponClassname, "weapon_m60", false))
    {
        return 150; // M60 max ammo
    }
    else if (StrContains(weaponClassname, "smg", false) != -1 ||
             StrEqual(weaponClassname, "weapon_smg", false) ||
             StrEqual(weaponClassname, "weapon_smg_silenced", false) ||
             StrEqual(weaponClassname, "weapon_smg_mp5", false))
    {
        return 650; // SMG max ammo
    }
    else if (StrContains(weaponClassname, "shotgun", false) != -1 ||
             StrEqual(weaponClassname, "weapon_shotgun_chrome", false) ||
             StrEqual(weaponClassname, "weapon_shotgun_spas", false) ||
             StrEqual(weaponClassname, "weapon_autoshotgun", false) ||
             StrEqual(weaponClassname, "weapon_pumpshotgun", false))
    {
        return 72; // Shotgun max ammo
    }
    else if (StrContains(weaponClassname, "sniper", false) != -1 ||
             StrEqual(weaponClassname, "weapon_sniper_military", false) ||
             StrEqual(weaponClassname, "weapon_hunting_rifle", false))
    {
        return 180; // Sniper max ammo
    }
    
    return 100; // Default fallback
}

public Action Timer_ClearSwitchingFlag(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        g_IsWeaponSwitching[client] = false;
        if (g_cvDebugMode.BoolValue)
            PrintToChat(client, "[DEBUG] Weapon switching flag cleared");
    }
    return Plugin_Stop;
}

bool DoesWeaponUseAmmoType(const char[] weaponClassname, int ammoType)
{
    return GetWeaponAmmoType(weaponClassname) == ammoType;
}

bool IsPrimaryWeapon(const char[] classname)
{
    return (StrContains(classname, "weapon_rifle", false) != -1
         || StrContains(classname, "weapon_smg", false) != -1
         || StrContains(classname, "weapon_shotgun", false) != -1
         || StrContains(classname, "weapon_sniper", false) != -1
         || StrEqual(classname, "weapon_m60", false)
         // Also check for item pickup names (without weapon_ prefix)
         || StrContains(classname, "rifle", false) != -1
         || StrContains(classname, "smg", false) != -1
         || StrContains(classname, "shotgun", false) != -1
         || StrContains(classname, "sniper", false) != -1
         || StrEqual(classname, "pumpshotgun", false)
         || StrEqual(classname, "autoshotgun", false)
         || StrEqual(classname, "hunting_rifle", false)
         || StrEqual(classname, "sniper_military", false)
         || StrEqual(classname, "smg_silenced", false)
         || StrEqual(classname, "smg_mp5", false));
}
