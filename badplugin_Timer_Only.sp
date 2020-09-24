
#define DEBUG

#define PLUGIN_NAME           "B.A.D. Plugin Timer Only"
#define PLUGIN_AUTHOR         "GameChaos / Hawk / GraemeUK"
#define PLUGIN_DESCRIPTION    "Bind Alias Detector Plugin"
#define PLUGIN_VERSION        "1.00"
#define PLUGIN_URL            ""

#define DEFAULT_FWD_LEVELS			"10, 15, 20, 25"
#define DEFAULT_NULL_LEVELS			"32, 64, 128, 256"

#define PREFIX						"[GC]"
#define LOG_PATH					"addons/sourcemod/logs/badplugin_log.txt"

#define LEFT_AND_RIGHT				(IN_MOVELEFT | IN_MOVERIGHT)
#define FWD_AND_BW					(IN_FORWARD | IN_BACK)

#define MAX_DETECTIONLEVEL			6
#define FWD_RELEASE_GRACETIME		4
#define INT_MAX						~(1<<31)

#include <sourcemod>
#include <sdktools>
#include <gamechaos>
#include <kztimer>

#pragma semicolon 1
#pragma newdecls required

// perfect w release count needed to notify/log or whatever
enum
{
	Fwd_None_Susp,
	Fwd_Notify_Susp,
	Fwd_Low_Susp,
	Fwd_Medium_Susp,
	Fwd_High_Susp,
}

// perfect strafe count needed to notify/log or whatever
enum
{
	Null_None_Susp,
	Null_Notify_Susp,
	Null_Low_Susp,
	Null_Medium_Susp,
	Null_High_Susp
}

ConVar g_cvFwdAutoban;
ConVar g_cvFwdLogging;
ConVar g_cvFwdMinBanlevel;
ConVar g_cvFwdMinLoglevel;
ConVar g_cvFwdMinChatloglevel;
ConVar g_cvFwdDetectionLevels;

ConVar g_cvNullAutoban;
ConVar g_cvNullLogging;
ConVar g_cvNullMinBanlevel;
ConVar g_cvNullMinLoglevel;
ConVar g_cvNullMinChatloglevel;
ConVar g_cvNullDetectionLevels;

ConVar g_cvCustomBanCmd;

int g_iFwdLevels[MAX_DETECTIONLEVEL] = 
{
	1,
	INT_MAX,
	INT_MAX,
	INT_MAX,
	INT_MAX,
	INT_MAX
};

int g_iNullLevels[MAX_DETECTIONLEVEL] = 
{
	1,
	INT_MAX,
	INT_MAX,
	INT_MAX,
	INT_MAX,
	INT_MAX
};

// -forward detection
int g_iFwdPerfectForward[MAXPLAYERS + 1];
int g_iFwdLastFwdTick[MAXPLAYERS + 1];
int g_iFwdDetectionLevel[MAXPLAYERS + 1];

// null detection
bool g_bJumped[MAXPLAYERS + 1];

int g_iNullPerfectCount[MAXPLAYERS + 1]; // perfect i.e. no overlap
int g_iNullTicksOverlapped[MAXPLAYERS + 1];
int g_iNullTicksNotHeldInAir[MAXPLAYERS + 1];
int g_iNullThreshold[MAXPLAYERS + 1]; // additional amount of strafes needed for a logging
int g_iNullDetectionLevel[MAXPLAYERS + 1];

char g_szDetectionLevels[MAX_DETECTIONLEVEL][] = 
{
	"0",
	"Very low detection",
	"Low detection",
	"Medium detection",
	"High detection",
	"INT_MAX",
};

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	HookEvent("player_jump", Event_PlayerJump, EventHookMode_Post);
	
	g_cvFwdAutoban = CreateConVar("sm_bad_fwd_autoban", "1", "Whether to autoban people who get detected for using a -forward bind.", 0, true, 0.0, true, 1.0);
	g_cvFwdLogging = CreateConVar("sm_bad_fwd_logging", "1", "Whether to log -forward bind detections or not.",                       0, true, 0.0, true, 1.0);
	g_cvFwdMinBanlevel = CreateConVar("sm_bad_fwd_min_banlevel", "4", "Minimum detection level to autoban people.",                   0, true, 1.0, true, 4.0);
	g_cvFwdMinLoglevel = CreateConVar("sm_bad_fwd_min_loglevel", "1", "Minimum detection level to log -forward detections.",                       0, true, 1.0, true, 4.0);
	g_cvFwdMinChatloglevel = CreateConVar("sm_bad_fwd_min_chatloglevel", "1", "Minimum detection level to log -forward detections to admins in chat.",    0, true, 1.0, true, 4.0);
	g_cvFwdDetectionLevels = CreateConVar("sm_bad_fwd_detectionlevels", DEFAULT_FWD_LEVELS, "-Forward detection levels for logging. 4 numbers, comma separated");
	
	g_cvNullAutoban = CreateConVar("sm_bad_null_autoban", "1", "Whether to autoban people who get detected for using the null movement script.",          0, true, 0.0, true, 1.0);
	g_cvNullLogging = CreateConVar("sm_bad_null_logging", "1", "Whether to log null script detections or not.",                                           0, true, 0.0, true, 1.0);
	g_cvNullMinBanlevel = CreateConVar("sm_bad_null_min_banlevel", "4", "Whether to autoban people who get detected for using the null movement script.", 0, true, 1.0, true, 4.0);
	g_cvNullMinLoglevel = CreateConVar("sm_bad_null_min_loglevel", "1", "Minimum detection level to log null detections.",                                         0, true, 1.0, true, 4.0);
	g_cvNullMinChatloglevel = CreateConVar("sm_bad_null_min_chatloglevel", "1", "Minimum detection level to log null detections to admins in chat.",                      0, true, 1.0, true, 4.0);
	g_cvNullDetectionLevels = CreateConVar("sm_bad_null_detectionlevels", DEFAULT_NULL_LEVELS, "Null detection levels for logging. 4 numbers separated by commas");
	
	g_cvCustomBanCmd = CreateConVar("sm_bad_custom_bancmd", "", "Custom commands to run when a player reaches minimum detection level.");
	
	g_cvFwdDetectionLevels.AddChangeHook(OnConVarChanged);
	g_cvNullDetectionLevels.AddChangeHook(OnConVarChanged);
	
	AutoExecConfig(.name = "badplugin");
}

public void OnConfigsExecuted()
{
	ParseFwdDetectionLevels();
	ParseNullDetectionLevels();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvFwdDetectionLevels)
	{
		ParseFwdDetectionLevels();
	}
	
	if (convar == g_cvNullDetectionLevels)
	{
		ParseNullDetectionLevels();
	}
}

public void OnClientConnected(int client)
{
	ResetFwdVars(client);
	ResetNullVars(client);
}

void ResetFwdVars(int client)
{
	g_iFwdPerfectForward[client] = 0;
	g_iFwdDetectionLevel[client] = Fwd_None_Susp;
}

void ResetNullVars(int client)
{
	g_iNullPerfectCount[client] = 0;
	g_iNullThreshold[client] = 0;
	g_iNullDetectionLevel[client] = Null_None_Susp;
}

void ParseFwdDetectionLevels()
{
	char szDetectionLevels[64];
	g_cvFwdDetectionLevels.GetString(szDetectionLevels, sizeof szDetectionLevels);
	
	// -2 because first and last values are always 0 and INT_MAX TODO: maybe fix this in the future
	int array[MAX_DETECTIONLEVEL - 2];
	SeparateIntsFromString(szDetectionLevels, ",", array, sizeof array);
	
	for (int i; i < sizeof array; i++)
	{
		if (i < sizeof(array) - 1
			&& array[i] >= array[i + 1] || array[i] < 1)
		{
			g_cvFwdAutoban.SetString(szDetectionLevels);
			PrintToChatAdmins("[badplugin] Invalid string of numbers supplied for sm_bad_fwd_detectionlevels. They have to be in ascending order and not negative or zero.");
			LogError("[badplugin] Invalid string of numbers supplied for sm_bad_fwd_detectionlevels. They have to be in ascending order and not negative or zero.");
			return;
		}
	}
	
	for (int i; i < sizeof array; i++)
	{
		// +1 because first value is always 0
		g_iFwdLevels[i + 1] = array[i];
	}
}

void ParseNullDetectionLevels()
{
	char szDetectionLevels[64];
	g_cvNullDetectionLevels.GetString(szDetectionLevels, sizeof szDetectionLevels);
	
	// -2 because first and last values are always 0 and INT_MAX TODO: maybe fix this in the future
	int array[MAX_DETECTIONLEVEL - 2];
	SeparateIntsFromString(szDetectionLevels, ",", array, sizeof array);
	
	for (int i; i < sizeof array; i++)
	{
		if (i < sizeof(array) - 1
			&& array[i] >= array[i + 1] || array[i] < 1)
		{
			g_cvNullDetectionLevels.SetString(szDetectionLevels);
			PrintToChatAdmins("[badplugin] Invalid string of numbers supplied for sm_bad_null_detectionlevels. They have to be in ascending order and not negative or zero.");
			LogError("[badplugin] Invalid string of numbers supplied for sm_bad_null_detectionlevels. They have to be in ascending order and not negative or zero.");
			return;
		}
	}
	
	for (int i; i < sizeof array; i++)
	{
		// +1 because first value is always 0
		g_iNullLevels[i + 1] = array[i];
	}
}

public void Event_PlayerJump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	g_bJumped[client] = true;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!IsValidClientExt(client, true) || IsFakeClient(client))
	{
		return;
	}
	
	int buttonReleased = GetEntProp(client, Prop_Data, "m_afButtonReleased");
	int buttonPressed = GetEntProp(client, Prop_Data, "m_afButtonPressed");
	
	CheckFwdRelease(client, buttons, buttonReleased);
	CheckOverlap(client, buttons, buttonPressed);
	//CheckKLook(client); // TODO
	
	g_bJumped[client] = false;
}

void CheckOverlap(int client, int buttons, int buttonPressed)
{
	if(KZTimer_GetTimerStatus(client))
	{
	
	
	     if (GetEntityFlags(client) & FL_ONGROUND
		    || GetEntityMoveType(client) != MOVETYPE_WALK)
	     {
		     return;
	     }
	
	     if (!g_cvNullAutoban.BoolValue && !g_cvNullLogging.BoolValue)
	     {
		     return;
	     }
	
	     if ((buttons & IN_MOVELEFT && buttons & IN_MOVERIGHT)
	       || (buttons & IN_FORWARD && buttons & IN_BACK))
	     {
		      g_iNullTicksOverlapped[client]++;
	     }
	
	     if (!(buttons & LEFT_AND_RIGHT) && !(buttons & FWD_AND_BW))
	     {
		       g_iNullTicksNotHeldInAir[client]++;
	     }
	
	     static float lastStrafeTime[MAXPLAYERS + 1];
	
	     if (buttonPressed & IN_FORWARD || buttonPressed & IN_BACK
		   || buttonPressed & IN_MOVELEFT || buttonPressed & IN_MOVERIGHT)
	     {
		       if (GetEngineTime() - lastStrafeTime[client] < 0.3)
		       {
			        if (g_iNullTicksOverlapped[client] == 0 && g_iNullTicksNotHeldInAir[client] == 0)
			        {
				         g_iNullPerfectCount[client]++;
			        }
			        else if (g_iNullTicksOverlapped[client] > 0)
			        {
				         ResetNullVars(client);
			        }
			        else if (g_iNullTicksNotHeldInAir[client] > 0)
			        {
			           	 g_iNullThreshold[client]++;
			        }
		      }
		
		      // reset stuff on end of last strafe
		      g_iNullTicksOverlapped[client] = 0;
		      g_iNullTicksNotHeldInAir[client] = 0;
		
		      lastStrafeTime[client] = GetEngineTime();
	      }
	      LogNullDetection(client);
    }
}

void CheckFwdRelease(int client, int buttons, int buttonReleased)
{
	if (GetEntityMoveType(client) != MOVETYPE_WALK)
	{
		return;
	}
	
	if (!g_cvFwdAutoban.BoolValue && !g_cvFwdLogging.BoolValue)
	{
		return;
	}
	
	if (buttonReleased & IN_FORWARD)
	{
		g_iFwdLastFwdTick[client] = GetGameTickCount();
	}
	
	if (g_bJumped[client])
	{
		if (buttonReleased & IN_FORWARD)
		{
			g_iFwdPerfectForward[client]++;
		}
		else if ((GetGameTickCount() - g_iFwdLastFwdTick[client]) <= FWD_RELEASE_GRACETIME // TODO find a good name for this magic number
				|| buttons & IN_FORWARD)
		{
			g_iFwdPerfectForward[client] = 0;
		}
	}
	LogFwdDetection(client);
}

void LogNullDetection(int client)
{
	for (int i = 0; i < MAX_DETECTIONLEVEL - 1; i++)
	{
		if (IsIntInRange(g_iNullPerfectCount[client] - g_iNullThreshold[client], g_iNullLevels[i], g_iNullLevels[i + 1]))
		{
			if (g_iNullDetectionLevel[client] != i)
			{
				if (g_cvNullLogging.BoolValue)
				{
					char szBuffer[256];
					FormatEx(szBuffer, sizeof szBuffer, "%s %s: %L detected for nulling [Strafes w/ no overlap: %i | Strafes with dead airtime: %i]", PREFIX, g_szDetectionLevels[i], client, g_iNullPerfectCount[client], g_iNullThreshold[client]);
					
					if (i >= g_cvNullMinChatloglevel.IntValue)
					{
						PrintToChatAdmins(szBuffer);
					}
					
					if (i >= g_cvNullMinLoglevel.IntValue)
					{
						LogToFile(LOG_PATH, szBuffer);
					}
				}
				
				if (i >= g_cvNullMinBanlevel.IntValue)
				{
					OnNullDetection(client);
				}
				
				g_iNullDetectionLevel[client] = i;
			}
			break;
		}
	}
}

void LogFwdDetection(int client)
{
	for (int i = 0; i < MAX_DETECTIONLEVEL - 1; i++)
	{
		if (IsIntInRange(g_iFwdPerfectForward[client], g_iFwdLevels[i], g_iFwdLevels[i + 1] - 1))
		{
			if (g_iFwdDetectionLevel[client] != i)
			{
				if (g_cvFwdLogging.BoolValue)
				{
					char szBuffer[256];
					FormatEx(szBuffer, sizeof szBuffer, "%s %s: %L detected for -w [Jumps with perfect -w: %i]", PREFIX, g_szDetectionLevels[i], client, g_iFwdPerfectForward[client]);
					
					if (i >= g_cvFwdMinChatloglevel.IntValue)
					{
						PrintToChatAdmins(szBuffer);
					}
					
					if (i >= g_cvFwdMinLoglevel.IntValue)
					{
						LogToFile(LOG_PATH, szBuffer);
					}
				}
				
				if (i >= g_cvFwdMinBanlevel.IntValue)
				{
					OnFwdDetection(client);
				}
				
				g_iFwdDetectionLevel[client] = i;
			}
			break;
		}
	}
}

// when the minimum detection level gets reached for ban
void OnFwdDetection(int client)
{
	if (g_cvFwdAutoban.BoolValue)
	{
		BanClient(client, 0, BANFLAG_AUTHID, "", "You have been banned for using a -forward bind.", "sm_ban", client);
	}
	
	RunCustomCmds(client);
	ResetFwdVars(client);
}

void OnNullDetection(int client)
{
	if (g_cvNullAutoban.BoolValue)
	{
		BanClient(client, 0, BANFLAG_AUTHID, "", "You have been banned for using the null movement script.", "sm_ban", client);
	}
	
	RunCustomCmds(client);
	ResetNullVars(client);
	KZTimer_StopTimer(client);	


	
}

void RunCustomCmds(int client)
{
	char szCustomCmds[1024];
	g_cvCustomBanCmd.GetString(szCustomCmds, sizeof szCustomCmds);
	ParseCustomCmdArgs(client, szCustomCmds, sizeof szCustomCmds);
	ServerCommand(szCustomCmds);
}

void ParseCustomCmdArgs(int client, char[] szCustomCmds, int strsize)
{
	// steam id
	char szSteamID[32];
	GetClientAuthId(client, AuthId_Steam2, szSteamID, sizeof szSteamID);
	
	ReplaceString(szCustomCmds, strsize, "{steamid}", szSteamID);
}
