#include <sourcemod>

#include <ripext>
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

#define URL "https://sourcejump.net/api/players/banned"

enum
{
	Action_Notify,
	Action_Kick,
	Action_TimerBan
};

ConVar gCV_APIKey;
ConVar gCV_Actions;

ArrayList gA_SteamIds;
bool gB_TimerBanned[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "SourceJump Bans",
	author = "Eric",
	description = "Checks if connecting clients are SourceJump banned.",
	version = "1.0.0",
	url = "https://steamcommunity.com/id/-eric"
};

public void OnPluginStart()
{
	gCV_APIKey = CreateConVar("sourcejump_bans_api_key", "", "SourceJump API key.", FCVAR_PROTECTED);
	gCV_Actions = CreateConVar("sourcejump_bans_actions", "2", "Action to take when a banned player joins the server? 0 = Notify admins, 1 = Kick player, 2 = Timer ban", _, true, 0.0, true, 2.0);
	AutoExecConfig();

	gA_SteamIds = new ArrayList(ByteCountToCells(32));
}

public void OnConfigsExecuted()
{
	char apiKey[64];
	gCV_APIKey.GetString(apiKey, sizeof(apiKey));

	if (apiKey[0] == '\0')
	{
		LogError("SourceJump API key is not set.");
		return;
	}

	HTTPRequest request = new HTTPRequest(URL);
	request.SetHeader("api-key", apiKey);
	request.Get(OnBannedPlayersReceived);
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	gB_TimerBanned[client] = false;

	char steamId[32];
	GetClientAuthId(client, AuthId_Steam3, steamId, sizeof(steamId));

	if (gA_SteamIds.FindString(steamId) == -1)
	{
		return;
	}

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamId);

	if (admin != INVALID_ADMIN_ID && admin.HasFlag(Admin_Custom6))
	{
		return;
	}

	switch (gCV_Actions.IntValue)
	{
		case Action_Notify:
		{
			PrintToAdmins("[SourceJump] %N %s is banned for cheating.", client, steamId);
		}
		case Action_Kick:
		{
			KickClient(client, "Your account is SourceJump banned");
		}
		case Action_TimerBan:
		{
			gB_TimerBanned[client] = true;
		}
	}
}

void OnBannedPlayersReceived(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("Failed to retrieve banned players. Response status: %d.", response.Status);
		return;
	}

	if (response.Data == null)
	{
		LogError("Invalid response data.");
		return;
	}

	gA_SteamIds.Clear();

	JSONArray players = view_as<JSONArray>(response.Data);
	JSONObject player;
	char steamId[32];

	for (int i = 0; i < players.Length; i++)
	{
		player = view_as<JSONObject>(players.Get(i));
		player.GetString("steamid", steamId, sizeof(steamId));

		gA_SteamIds.PushString(steamId);

		delete player;
	}

	delete players;
}

/**
 * Called by Shavit's timer before a player finishes their run.
 */
public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot)
{
	if (gB_TimerBanned[client])
	{
		PrintToChat(client, "[SourceJump] Your time (%f) did not save because your account is SourceJump banned.", snapshot.fCurrentTime);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

/**
 * Prints a message to all admins in the chat area.
 *
 * @param format        Formatting rules.
 * @param any           Variable number of format parameters.
 * @noreturn
 */
stock void PrintToAdmins(const char[] format, any ...)
{
	char buffer[300];
	VFormat(buffer, sizeof(buffer), format, 2);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (CheckCommandAccess(i, "", ADMFLAG_GENERIC))
			{
				PrintToChat(i, "%s", buffer);
			}
		}
	}
}
