#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <shavit>
#include <cstrike>
#include <sdktools>

#undef REQUIRE_PLUGIN
// for MapChange type
#include <mapchooser>

#define PLUGIN_VERSION "2.0.0.4"

Database g_hDatabase;
char g_cSQLPrefix[32];

#define DEBUG 1

#if defined DEBUG
bool g_bDebug;
#endif

/* ConVars */
ConVar g_cvRTVRequiredPercentage;
ConVar g_cvRTVAllowSpectators;
ConVar g_cvRTVMinimumPoints;
ConVar g_cvRTVDelayTime;

ConVar g_cvMapVoteStartTime;
ConVar g_cvMapVoteDuration;
ConVar g_cvMapVoteBlockMapInterval;
ConVar g_cvMapVoteExtendLimit;
ConVar g_cvMapVoteEnableNoVote;
ConVar g_cvMapVoteExtendTime;
ConVar g_cvMapVoteShowTier;
ConVar g_cvMapVoteRunOff;
ConVar g_cvMapVoteRunOffPerc;
ConVar g_cvMapVoteRevoteTime;
ConVar g_cvDisplayTimeRemaining;

ConVar sm_nextmap = null;
//ConVar mp_win_panel_display_time = null;
//ConVar mp_maxrounds = null;
ConVar mp_teamname_1 = null;
ConVar mp_teamname_2 = null;
/* Map arrays */
ArrayList g_aMapList;
ArrayList g_aOldMaps;

StringMap g_smMapList;
//map, id

/* Map Data */
char g_cMapName[PLATFORM_MAX_PATH];
char g_cNextMap[PLATFORM_MAX_PATH];

char g_cCurrentMapID[32];

MapChange g_ChangeTime;

bool g_bMapVoteStarted;
bool g_bMapVoteFinished;
bool g_bLastRound;
float g_fMapStartTime;
float g_fLastMapvoteTime = 0.0;

int g_iExtendCount;

Menu g_hNominateMenu;

#define MAXTIERS 10 + 1
//0-10
Menu g_hTiersMenu[MAXTIERS];
Menu g_hNormalMenu;
Menu g_hVoteMenu;

/* Player Data */
bool g_bRockTheVote[MAXPLAYERS + 1];
char g_cNominatedMap[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
int g_iNominateCount;
bool g_bStay[MAXPLAYERS + 1];

Handle g_hRetryTimer = null;
Handle g_hForward_OnRTV = null;
Handle g_hForward_OnUnRTV = null;
Handle g_hForward_OnStay = null;
Handle g_hForward_OnLeave = null;
Handle g_hForward_OnSuccesfulRTV = null;
Handle g_hForward_OnTeamNameChange = null;


public Plugin myinfo =
{
	name = "shavit - MapChooser",
	author = "SlidyBat",
	description = "Automated Map Voting and nominating with Shavit timer integration",
	version = PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	g_hForward_OnRTV = CreateGlobalForward( "SMC_OnRTV", ET_Event, Param_Cell );
	g_hForward_OnUnRTV = CreateGlobalForward( "SMC_OnUnRTV", ET_Event, Param_Cell );
	g_hForward_OnStay = CreateGlobalForward( "SMC_OnStay", ET_Event, Param_Cell );
	g_hForward_OnLeave = CreateGlobalForward( "SMC_Leave", ET_Event, Param_Cell );
	g_hForward_OnSuccesfulRTV = CreateGlobalForward( "SMC_OnSuccesfulRTV", ET_Event );
	g_hForward_OnTeamNameChange = CreateGlobalForward( "SMC_OnTeamNameChange", ET_Event, Param_String, Param_String );


	CreateNative( "SMC_GetNextMap", Native_GetNextMap );
	CreateNative( "SMC_SetNextMap", Native_SetNextMap );
	CreateNative( "SMC_ChangeMap", Native_ChangeMap );

	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent( "round_start", OnRoundStartPost );
	HookEvent( "round_end", OnRoundEndPre, EventHookMode_Pre );
	HookEvent( "cs_win_panel_match", Event_MatchEnd );
	LoadTranslations( "mapchooser.phrases" );
	LoadTranslations( "common.phrases" );
	LoadTranslations( "rockthevote.phrases" );
	LoadTranslations( "nominations.phrases" );
	LoadTranslations( "basetriggers.phrases" );

	g_aMapList = new ArrayList( ByteCountToCells( PLATFORM_MAX_PATH ) );
	g_aOldMaps = new ArrayList(ByteCountToCells( 32 ));

	g_smMapList = new StringMap();

	g_cvMapVoteBlockMapInterval = CreateConVar( "smc_mapvote_blockmap_interval", "1", "How many maps should be played before a map can be nominated again", _, true, 0.0, false );
	g_cvMapVoteEnableNoVote = CreateConVar( "smc_mapvote_enable_novote", "1", "Whether players are able to choose 'No Vote' in map vote", _, true, 0.0, true, 1.0 );
	g_cvMapVoteExtendLimit = CreateConVar( "smc_mapvote_extend_limit", "3", "How many times players can choose to extend a single map ( 0 = block extending )", _, true, 0.0, false );
	g_cvMapVoteExtendTime = CreateConVar( "smc_mapvote_extend_time", "10", "How many minutes should the map be extended by if the map is extended through a mapvote", _, true, 1.0, false );
	g_cvMapVoteShowTier = CreateConVar( "smc_mapvote_show_tier", "1", "Whether the map tier should be displayed in the map vote", _, true, 0.0, true, 1.0 );
	g_cvMapVoteDuration = CreateConVar( "smc_mapvote_duration", "1", "Duration of time in minutes that map vote menu should be displayed for", _, true, 0.1, false );
	g_cvMapVoteStartTime = CreateConVar( "smc_mapvote_start_time", "5", "Time in minutes before map end that map vote starts", _, true, 1.0, false );

	g_cvRTVAllowSpectators = CreateConVar( "smc_rtv_allow_spectators", "1", "Whether spectators should be allowed to RTV", _, true, 0.0, true, 1.0 );
	g_cvRTVMinimumPoints = CreateConVar( "smc_rtv_minimum_points", "-1", "Minimum number of points a player must have before being able to RTV, or -1 to allow everyone", _, true, -1.0, false );
	g_cvRTVDelayTime = CreateConVar( "smc_rtv_delay", "5", "Time in minutes after map start before players should be allowed to RTV", _, true, 0.0, false );
	g_cvRTVRequiredPercentage = CreateConVar( "smc_rtv_required_percentage", "50", "Percentage of players who have RTVed before a map vote is initiated", _, true, 1.0, true, 100.0 );

	g_cvMapVoteRunOff = CreateConVar( "smc_mapvote_runoff", "1", "Hold run of votes if winning choice is less than a certain margin", _, true, 0.0, true, 1.0 );
	g_cvMapVoteRunOffPerc = CreateConVar( "smc_mapvote_runoffpercent", "50", "If winning choice has less than this percent of votes, hold a runoff", _, true, 0.0, true, 100.0 );
	g_cvMapVoteRevoteTime = CreateConVar( "smc_mapvote_revotetime", "0", "How many minutes after a failed mapvote before rtv is enabled again", _, true, 0.0 );
	g_cvDisplayTimeRemaining = CreateConVar( "smc_display_timeleft", "1", "Display remaining messages in chat", _, true, 0.0, true, 1.0 );

	AutoExecConfig();

	RegAdminCmd( "sm_extend", Command_Extend, ADMFLAG_CHANGEMAP, "Admin command for extending map" );
	RegAdminCmd( "sm_forcemapvote", Command_ForceMapVote, ADMFLAG_RCON, "Admin command for forcing the end of map vote" );
	RegAdminCmd( "sm_reloadmaplist", Command_ReloadMaplist, ADMFLAG_CHANGEMAP, "Admin command for forcing maplist to be reloaded" );

	RegConsoleCmd( "sm_nominate", Command_Nominate, "Lets players nominate maps to be on the end of map vote" );
	RegConsoleCmd( "sm_unnominate", Command_UnNominate, "Removes nominations" );
	RegConsoleCmd( "sm_rtv", Command_RockTheVote, "Lets players Rock The Vote" );
	RegConsoleCmd( "sm_unrtv", Command_UnRockTheVote, "Lets players un-Rock The Vote" );
	RegConsoleCmd( "sm_stay", Command_Stay, "Let's the players stay on the map" );
	RegConsoleCmd( "sm_leave", Command_Leave, "Let's the players leave on map" );
	RegConsoleCmd( "sm_unstay", Command_Leave, "Let's the players leave on map" );

	AddCommandListener( Command_SMap, "sm_smap" );
	AddCommandListener( Command_SMap, "sm_map" );
	AddCommandListener( Listener_Nextmap, "nextmap" );

	sm_nextmap = FindConVar( "sm_nextmap" );
	//mp_maxrounds = FindConVar( "mp_maxrounds" );
	//mp_win_panel_display_time = FindConVar( "mp_win_panel_display_time" );
	mp_teamname_1 = FindConVar( "mp_teamname_1" );
	mp_teamname_2 = FindConVar( "mp_teamname_2" );

	char error[512];
	g_hDatabase = SQLite_UseDatabase( "db_mapcycle", error, sizeof( error ) );
	if( error[0] != 0 )
	{
		LogError(error);
	}

	#if defined DEBUG
	RegConsoleCmd( "sm_smcdebug", Command_Debug );
	#endif
}

public void OnMapEnd()
{
	DebugPrint( "#### Debug Print: OnMapEnd" );
}

public void OnMapStart()
{
	DebugPrint( "#### Debug Print: OnMapStart" );

	char mapsplit[2][PLATFORM_MAX_PATH];
	GetCurrentMap( g_cMapName, PLATFORM_MAX_PATH );
	ReplaceString( g_cMapName, PLATFORM_MAX_PATH, "workshop/", "", false) ;
	ExplodeString( g_cMapName, "/", mapsplit, 2, 64 );

	strcopy(g_cCurrentMapID, 32, mapsplit[0]);
	g_cMapName = mapsplit[1];

	g_fMapStartTime = GetGameTime();
	g_fLastMapvoteTime = 0.0;
	g_iExtendCount = 0;
	g_bMapVoteFinished = false;
	g_bMapVoteStarted = false;
	g_bLastRound = false;
	g_cNextMap[0] = 0;
	g_iNominateCount = 0;

	for( int i = 1; i <= MaxClients; ++i )
	{
		g_cNominatedMap[i][0] = 0;
	}

	ClearRTV();

	for( int i = 1; i <= MaxClients; ++i )
	{
		g_bStay[i] = false;
	}

	CreateTimer( 2.0, Timer_OnMapTimeLeftChanged, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
}

public void Event_MatchEnd( Event event, const char[] name, bool dontBroadcast )
{
	static int s_LastAttemptTime = 0;

	if( GetTime() - s_LastAttemptTime < 10 )
	{
		return;
	}

	s_LastAttemptTime = GetTime();


	if( g_cvMapVoteBlockMapInterval.IntValue > 0 )
	{
		g_aOldMaps.PushString( g_cCurrentMapID );
		if( g_aOldMaps.Length > g_cvMapVoteBlockMapInterval.IntValue )
		{
			g_aOldMaps.Erase( 0 );
		}
	}

	g_iExtendCount = 0;
	g_bMapVoteFinished = false;
	g_bMapVoteStarted = false;
	g_iNominateCount = 0;
	for( int i = 1; i <= MaxClients; ++i )
	{
		g_cNominatedMap[i][0] = 0;
	}

	for( int i = 1; i <= MaxClients; ++i )
	{
		g_bStay[i] = false;
	}


	ClearRTV();

	DebugPrint( "#### Debug Print: Event_MatchEnd" );

	ChangeMapDelayed( g_cNextMap );
}

public void OnConfigsExecuted()
{
	DebugPrint( "#### Debug Print: OnConfigsExecuted" );

	// reload maplist array
	LoadMapList();
}

public Action OnRoundStartPost( Event event, const char[] name, bool dontBroadcast )
{
	DebugPrint( "#### Debug Print: OnRoundStartPost" );
	sm_nextmap.SetString( "", false, false );
}

public Action OnRoundEndPre( Event event, const char[] name, bool dontBroadcast )
{
	if(g_bLastRound)
	{
		DebugPrint( "#### Debug Print: Event_MatchEnd" );
		ChangeMapDelayed( g_cNextMap, 7.0 );
	}
	return Plugin_Continue;
}

public Action Timer_OnMapTimeLeftChanged( Handle Timer )
{
	#if defined DEBUG
	if( g_bDebug )
	{
		DebugPrint( "[SMC] OnMapTimeLeftChanged: maplist_length=%i mapvote_started=%s mapvotefinished=%s", g_aMapList.Length, g_bMapVoteStarted ? "true" : "false", g_bMapVoteFinished ? "true" : "false" );
	}
	#endif

	int timeleft;
	if( GetMapTimeLeft( timeleft ) )
	{
		if( !g_bMapVoteStarted && !g_bMapVoteFinished )
		{
			int mapvoteTime = timeleft - RoundFloat( g_cvMapVoteStartTime.FloatValue * 60.0 );
			switch( mapvoteTime )
			{
				case ( 10 * 60 ):
				{
					PrintToChatAll( "[SMC] 10 minutes until map vote" );
				}
				case ( 5 * 60 ):
				{
					PrintToChatAll( "[SMC] 5 minutes until map vote" );
				}
				case 60:
				{
					PrintToChatAll( "[SMC] 1 minute until map vote" );
				}
				case 30:
				{
					PrintToChatAll( "[SMC] 30 seconds until map vote" );
				}
				case 5:
				{
					PrintToChatAll( "[SMC] 5 seconds until map vote" );
				}
			}
		}
		else if( g_bMapVoteFinished && g_cvDisplayTimeRemaining.BoolValue )
		{
			switch( timeleft )
			{
				case ( 30 * 60 ):
				{
					PrintToChatAll( "[SMC] 30 minutes remaining" );
				}
				case ( 20 * 60 ):
				{
					PrintToChatAll( "[SMC] 20 minutes remaining" );
				}
				case ( 10 * 60 ):
				{
					PrintToChatAll( "[SMC] 10 minutes remaining" );
				}
				case ( 5 * 60 ):
				{
					PrintToChatAll( "[SMC] 5 minutes remaining" );
				}
				case 60:
				{
					PrintToChatAll( "[SMC] 1 minute remaining" );
				}
				case 10:
				{
					PrintToChatAll( "[SMC] 10 seconds remaining" );
				}
				case 5:
				{
					PrintToChatAll( "[SMC] 5 seconds remaining" );
				}
				case 3:
				{
					PrintToChatAll( "[SMC] 3 seconds remaining" );
				}
				case 2:
				{
					PrintToChatAll( "[SMC] 2 seconds remaining" );
				}
				case 1:
				{
					PrintToChatAll( "[SMC] 1 seconds remaining" );
				}
			}
		}
	}

	if( g_aMapList.Length && !g_bMapVoteStarted && !g_bMapVoteFinished )
	{
		CheckTimeLeft();
	}

	if(timeleft < 5)
	{
		g_bLastRound = true;
	}

	PrepareScoreBoard(timeleft);
}

Action PrepareScoreBoard(int timeleft)
{
	char teamname1[64];
	char stimeleft[64];
	char teamname2[64];
	float time = float( timeleft );

	FormatSeconds( time, stimeleft, sizeof( stimeleft ), false );
	if(g_bLastRound)
	{
		teamname1 = "Timeleft:\nFinal Round";
	}
	else
	{
		FormatEx( teamname1, sizeof( teamname1 ), "Timeleft:\n%s", stimeleft );
	}
	if( !IsCharNumeric( g_cNextMap[0] ) && !IsCharAlpha( g_cNextMap[0] ) )
	{
		teamname2 = "Next Map:\nPending Vote";
	}
	else
	{
		FormatEx( teamname2, sizeof( teamname2 ), "Next Map:\n%s", g_cNextMap );
	}

	Action result = Plugin_Continue;
	Call_StartForward(g_hForward_OnTeamNameChange);

	Call_PushStringEx(teamname1, 64, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(teamname2, 64, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);

	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return result;
	}

	mp_teamname_1.SetString( teamname1, true );
	mp_teamname_2.SetString( teamname2, true );

	return Plugin_Continue;
}

void CheckTimeLeft()
{
	int timeleft;
	if( GetMapTimeLeft( timeleft ) && timeleft > 0 )
	{
		int startTime = RoundFloat( g_cvMapVoteStartTime.FloatValue * 60.0 );
		#if defined DEBUG
		if( g_bDebug )
		{
			DebugPrint( "[SMC] CheckTimeLeft: timeleft=%i startTime=%i", timeleft, startTime );
		}
		#endif

		if( timeleft - startTime <= 0 )
		{
			#if defined DEBUG
			if( g_bDebug )
			{
				DebugPrint( "[SMC] CheckTimeLeft: Initiating map vote ...", timeleft, startTime );
			}
			#endif

			InitiateMapVote( MapChange_MapEnd );
		}
	}
	#if defined DEBUG
	else
	{
		if( g_bDebug )
		{
			DebugPrint( "[SMC] CheckTimeLeft: GetMapTimeLeft=%s timeleft=%i", GetMapTimeLeft( timeleft ) ? "true" : "false", timeleft );
		}
	}
	#endif
}

public void OnClientDisconnect( int client )
{
	// clear player data
	g_bRockTheVote[client] = false;
	g_bStay[client] = false;
	if(g_cNominatedMap[client][0] != 0)
	{
		--g_iNominateCount;
	}
	g_cNominatedMap[client][0] = 0;
}

public void OnClientDisconnect_Post( int client )
{
	CheckRTV();
}

public void OnClientSayCommand_Post( int client, const char[] command, const char[] sArgs )
{
	if( StrEqual( sArgs, "rtv", false ) || StrEqual( sArgs, "rockthevote", false ) )
	{
		ReplySource old = SetCmdReplySource( SM_REPLY_TO_CHAT );

		Command_RockTheVote( client, 0 );

		SetCmdReplySource( old );
	}
	else if( StrEqual( sArgs, "nominate", false ) )
	{
		ReplySource old = SetCmdReplySource( SM_REPLY_TO_CHAT );

		Command_Nominate( client, 0 );

		SetCmdReplySource( old );
	}
}

void InitiateMapVote( MapChange when )
{
	g_ChangeTime = when;
	g_bMapVoteStarted = true;

	if ( IsVoteInProgress() )
	{
		// Can't start a vote, try again in 5 seconds.
		//g_RetryTimer = CreateTimer( 5.0, Timer_StartMapVote, _, TIMER_FLAG_NO_MAPCHANGE );

		DataPack data;
		g_hRetryTimer = CreateDataTimer( 5.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE );
		data.WriteCell( when );
		data.Reset();
		return;
	}

	// create menu
	Menu menu = new Menu( Handler_MapVoteMenu, MENU_ACTIONS_ALL );
	menu.VoteResultCallback = Handler_MapVoteFinished;
	menu.Pagination = MENU_NO_PAGINATION;
	menu.SetTitle( "Vote Nextmap" );

	int mapsToAdd = 8;
	if( g_cvMapVoteExtendLimit.IntValue > 0 && g_iExtendCount < g_cvMapVoteExtendLimit.IntValue )
	{
		mapsToAdd--;
	}

	if( g_cvMapVoteEnableNoVote.BoolValue )
	{
		mapsToAdd--;
	}

	char map[PLATFORM_MAX_PATH];
	char mapdisplay[PLATFORM_MAX_PATH + 32];


	for( int i = 0; i <= MaxClients; ++i )
	{
		if(g_cNominatedMap[i][0] != 0)
		{
			if(mapsToAdd > 0)
			{
				strcopy(map, PLATFORM_MAX_PATH, g_cNominatedMap[i]);
				if( g_cvMapVoteShowTier.BoolValue )
				{
					int tier = Shavit_GetMapTier( map );


					Format( mapdisplay, sizeof( mapdisplay ), "[T%i] %s", tier, map );
				}
				else
				{
					strcopy( mapdisplay, sizeof( mapdisplay ), map );
				}

				menu.AddItem( map, mapdisplay );

				--mapsToAdd;
			}
		}
	}

	for( int i = 0; i < mapsToAdd; ++i )
	{
		int rand = GetRandomInt( 0, g_aMapList.Length - 1 );
		g_aMapList.GetString( rand, map, sizeof( map ) );
		char id[32];
		g_smMapList.GetString( map, id, 32 );

		if( StrEqual( map, g_cMapName ) )
		{
			// don't add current map to vote
			i--;
			continue;
		}

		int idx = g_aOldMaps.FindString( id );
		if( idx != -1 )
		{
			// map already played recently, get another map
			i--;
			continue;
		}

		if( g_cvMapVoteShowTier.BoolValue )
		{
			int tier = Shavit_GetMapTier( map );

			Format( mapdisplay, sizeof( mapdisplay ), "[T%i] %s", tier, map );
		}
		else
		{
			strcopy( mapdisplay, sizeof( mapdisplay ), map );
		}


		menu.AddItem( map, mapdisplay );
	}

	if( when == MapChange_MapEnd && g_cvMapVoteExtendLimit.IntValue > 0 && g_iExtendCount < g_cvMapVoteExtendLimit.IntValue )
	{
		menu.AddItem( "extend", "Extend Map" );
	}
	else if( when == MapChange_Instant )
	{
		menu.AddItem( "dontchange", "Don't Change" );
	}

	menu.NoVoteButton = g_cvMapVoteEnableNoVote.BoolValue;
	menu.ExitButton = false;
	menu.DisplayVoteToAll( RoundFloat( g_cvMapVoteDuration.FloatValue * 60.0 ) );

	PrintToChatAll( "[SMC] %t", "Nextmap Voting Started" );
}

public void Handler_MapVoteFinished( Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info )
{
	if ( g_cvMapVoteRunOff.BoolValue && num_items > 1 )
	{
		float winningvotes = float( item_info[0][VOTEINFO_ITEM_VOTES] );
		float required = num_votes * ( g_cvMapVoteRunOffPerc.FloatValue / 100.0 );

		if ( winningvotes < required )
		{
			/* Insufficient Winning margin - Lets do a runoff */
			g_hVoteMenu = new Menu( Handler_MapVoteMenu, MENU_ACTIONS_ALL );
			g_hVoteMenu.SetTitle( "Runoff Vote Nextmap" );
			g_hVoteMenu.VoteResultCallback = Handler_VoteFinishedGeneric;

			char map[PLATFORM_MAX_PATH];
			char info1[PLATFORM_MAX_PATH];
			char info2[PLATFORM_MAX_PATH];

			menu.GetItem( item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof( map ), _, info1, sizeof( info1 ) );
			g_hVoteMenu.AddItem( map, info1 );
			menu.GetItem( item_info[1][VOTEINFO_ITEM_INDEX], map, sizeof( map ), _, info2, sizeof( info2 ) );
			g_hVoteMenu.AddItem( map, info2 );

			g_hVoteMenu.ExitButton = true;
			g_hVoteMenu.DisplayVoteToAll( RoundFloat( g_cvMapVoteDuration.FloatValue * 60.0 ) );

			/* Notify */
			float map1percent = float( item_info[0][VOTEINFO_ITEM_VOTES] )/ float( num_votes ) * 100;
			float map2percent = float( item_info[1][VOTEINFO_ITEM_VOTES] )/ float( num_votes ) * 100;


			PrintToChatAll( "[SM] %t", "Starting Runoff", g_cvMapVoteRunOffPerc.FloatValue, info1, map1percent, info2, map2percent );
			LogMessage( "Voting for next map was indecisive, beginning runoff vote" );

			return;
		}
	}

	Handler_VoteFinishedGeneric( menu, num_votes, num_clients, client_info, num_items, item_info );
}

public Action Timer_StartMapVote( Handle timer, DataPack data )
{
	if ( timer == g_hRetryTimer )
	{
		g_hRetryTimer = null;
	}

	if ( !g_aMapList.Length || g_bMapVoteFinished || g_bMapVoteStarted )
	{
		return Plugin_Stop;
	}

	MapChange when = view_as<MapChange>( data.ReadCell() );

	InitiateMapVote( when );

	return Plugin_Stop;
}

public void Handler_VoteFinishedGeneric( Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info )
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];

	menu.GetItem( item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof( map ), _, displayName, sizeof( displayName ) );

	char debug2[256];
	FormatEx( debug2, sizeof( debug2 ), "Handler_VoteFinishedGeneric, item_info 0: %s", displayName );
	DebugPrint( debug2 );

	PrintToChatAll( "#1 vote was %s ( %s )", map, ( g_ChangeTime == MapChange_Instant ) ? "instant" : "map end" );

	if( StrEqual( map, "extend" ) )
	{
		g_iExtendCount++;

		int time;
		if( GetMapTimeLimit( time ) )
		{
			if( time > 0 )
			{
				ExtendMapTimeLimit( g_cvMapVoteExtendTime.IntValue * 60 );
			}
		}

		PrintToChatAll( "[SMC] %t", "Current Map Extended", RoundToFloor( float( item_info[0][VOTEINFO_ITEM_VOTES] )/float( num_votes )*100 ), num_votes );
		LogAction( -1, -1, "Voting for next map has finished. The current map has been extended." );

		// We extended, so we'll have to vote again.
		g_bMapVoteStarted = false;
		g_bLastRound = false;
		g_fLastMapvoteTime = GetGameTime();

		ClearRTV();

		for( int i = 1; i <= MaxClients; ++i )
		{
			g_bStay[i] = false;
		}
	}
	else if( StrEqual( map, "dontchange" ) )
	{
		PrintToChatAll( "[SMC] %t", "Current Map Stays", RoundToFloor( float( item_info[0][VOTEINFO_ITEM_VOTES] )/float( num_votes )*100 ), num_votes );
		LogAction( -1, -1, "Voting for next map has finished. 'No Change' was the winner" );

		g_bMapVoteFinished = false;
		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetGameTime();

		ClearRTV();

		for( int i = 1; i <= MaxClients; ++i )
		{
			g_bStay[i] = false;
		}
	}
	else
	{
		if( g_ChangeTime == MapChange_MapEnd )
		{
			Set_NextMap( map );
		}
		else if( g_ChangeTime == MapChange_Instant )
		{
			// Not sure what i'm doing here, will come back to that later
			int total = RoundToFloor( GetPlayerCount( g_cvRTVAllowSpectators.BoolValue ) * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
			if( total == 0 )
			{
				total = 1;
			}
			if( total - GetRTVCount() <= 0 )
			{
				Call_StartForward( g_hForward_OnSuccesfulRTV );
				Call_Finish();
			}

			ChangeMapDelayed( map );

			ClearRTV();

			for( int i = 1; i <= MaxClients; ++i )
			{
				g_bStay[i] = false;
			}
		}

		g_bMapVoteStarted = false;
		g_bMapVoteFinished = true;

		PrintToChatAll( "[SMC] %t", "Nextmap Voting Finished", map, RoundToFloor( float( item_info[0][VOTEINFO_ITEM_VOTES] )/float( num_votes )*100 ), num_votes );
		LogAction( -1, -1, "Voting for next map has finished. Nextmap: %s.", map );
	}
}

public int Handler_MapVoteMenu( Menu menu, MenuAction action, int param1, int param2 )
{
	switch( action )
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Display:
		{
			Panel panel = view_as<Panel>( param2 );
			panel.SetTitle( "Vote Nextmap" );
		}

		case MenuAction_DisplayItem:
		{
			if ( menu.ItemCount - 1 == param2 )
			{
				char map[PLATFORM_MAX_PATH], buffer[255];
				menu.GetItem( param2, map, sizeof( map ) );
				if ( strcmp( map, "extend", false ) == 0 )
				{
					buffer = "Extend Map";
					return RedrawMenuItem( buffer );
				}
				else if ( strcmp( map, "novote", false ) == 0 )
				{
					buffer =  "No Vote";
					return RedrawMenuItem( buffer );
				}
			}
		}

		case MenuAction_VoteCancel:
		{
			// If we receive 0 votes, pick at random.
			if( param1 == VoteCancel_NoVotes )
			{
				int count = menu.ItemCount;
				char map[PLATFORM_MAX_PATH];
				menu.GetItem( 0, map, sizeof( map ) );
				char debug1[256];
				FormatEx( debug1, sizeof( debug1 ), "VoteCancel_NoVotes, item 0: %s", map );
				DebugPrint( debug1 );

				// Make sure the first map in the menu isn't one of the special items.
				// This would mean there are no real maps in the menu, because the special items are added after all maps. Don't do anything if that's the case.
				if( strcmp( map, "extend", false ) != 0 && strcmp( map, "dontchange", false ) != 0 )
				{
					// Get a random map from the list.

					// Make sure it's not one of the special items.
					do
					{
						int item = GetRandomInt( 0, count - 1 );
						menu.GetItem( item, map, sizeof( map ) );
					}
					while( strcmp( map, "extend", false ) == 0 || strcmp( map, "dontchange", false ) == 0 );

					Set_NextMap( map );

					PrintToChatAll( "[SMC] %t", "Nextmap Voting Finished", map, 0, 0 );
					LogAction( -1, -1, "Voting for next map has finished. Nextmap: %s.", map );
					g_bMapVoteFinished = true;
					if( g_ChangeTime == MapChange_Instant )
					{
						ChangeMapDelayed( map );
					}
				}
			}

			g_bMapVoteStarted = false;
		}
	}

	return 0;
}

// extends map while also notifying players and setting plugin data
void ExtendMap( int time = 0 )
{
	if( time == 0 )
	{
		time = RoundFloat( g_cvMapVoteExtendTime.FloatValue * 60 );
	}

	ExtendMapTimeLimit( time );
	PrintToChatAll( "[SMC] The map was extended for %.1f minutes", time / 60.0 );

	g_bMapVoteStarted = false;
	g_bMapVoteFinished = false;
	g_bLastRound = false;
}

void LoadMapList()
{
	g_hDatabase.Query( LoadMapListCallback, "SELECT WorkshopID, Map FROM db_maplist", _, DBPrio_High );
}

public void LoadMapListCallback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SMC] - ( LoadMapListCallback ) - %s", error );
		return;
	}
	static int s_LastAttemptTime = 0;
	if((GetTime() - s_LastAttemptTime) < 5)
	{
		LogMessage("LoadMapListCallback Fired multiple times");
		return;
	}

	s_LastAttemptTime = GetTime();

	g_aMapList.Clear();
	g_smMapList.Clear();

	while( results.FetchRow() )
	{
		char map[PLATFORM_MAX_PATH];
		char id[32];

		results.FetchString( 0, id, sizeof( id ) );
		results.FetchString( 1, map, sizeof( map ) );

		//no validation since maps will be downloaded regardless

		g_aMapList.PushString( map );
		g_smMapList.SetString( map, id, true );
	}

	SortADTArrayCustom(g_aMapList, SortNominateMenu);

	CreateNominateMenu();
}

bool SMC_FindMap( const char[] mapname, char[] output, int maxlen )
{

	int length = g_aMapList.Length;
	for( int i = 0; i < length; ++i )
	{
		char entry[PLATFORM_MAX_PATH];
		g_aMapList.GetString( i, entry, sizeof( entry ) );

		if( StrContains( entry, mapname ) != -1 )
		{
			strcopy( output, maxlen, entry );
			return true;
		}
	}

	return false;

}

bool IsRTVEnabled()
{
	float time = GetGameTime();

	if( g_fLastMapvoteTime != 0.0 )
	{
		if( time - g_fLastMapvoteTime > g_cvMapVoteRevoteTime.FloatValue * 60 )
		{
			return true;
		}
	}
	else if( time - g_fMapStartTime > g_cvRTVDelayTime.FloatValue * 60 )
	{
		return true;
	}
	return false;
}

void ClearRTV()
{
	for( int i = 1; i <= MaxClients; ++i )
	{
		g_bRockTheVote[i] = false;
	}
}

/* Timers */
public Action Timer_ChangeMap( Handle timer )
{
	static int s_LastAttemptTime = 0;

	char id[32];
	g_smMapList.GetString( g_cNextMap, id, 32 );
	PrintToConsoleAll( "map: '%s' id: '%s'", g_cNextMap, id );

	char message[256];
	FormatEx( message, sizeof( message ), "#### Debug Print: Changed map to %s", id );
	DebugPrint( message );
	if((GetTime() - s_LastAttemptTime) > 10)
	{
		ServerCommand( "host_workshop_map %s", id );
		s_LastAttemptTime = GetTime();
	}
	else
	{
		LogMessage("Server Attempted multiple map changes. \nmap: '%s' id: '%s'", g_cNextMap, id);
	}

	return Plugin_Handled;
}

/* Commands */
public Action Command_Extend( int client, int args )
{
	int extendtime;
	if( args > 0 )
	{
		char sArg[8];
		GetCmdArg( 1, sArg, sizeof( sArg ) );
		extendtime = RoundFloat( StringToFloat( sArg ) * 60 );
	}
	else
	{
		extendtime = RoundFloat( g_cvMapVoteExtendTime.FloatValue * 60.0 );
	}

	ExtendMap( extendtime );

	return Plugin_Handled;
}

public Action Command_ForceMapVote( int client, int args )
{
	if( g_bMapVoteStarted || g_bMapVoteFinished )
	{
		ReplyToCommand( client, "[SMC] Map vote already %s", ( g_bMapVoteStarted ) ? "initiated" : "finished" );
	}
	else
	{
		InitiateMapVote( MapChange_Instant );
	}

	return Plugin_Handled;
}

public Action Command_ReloadMaplist( int client, int args )
{
	LoadMapList();

	return Plugin_Handled;
}

public Action Command_Nominate( int client, int args )
{
	if( args < 1 )
	{
		OpenNominateMenu( client );
		return Plugin_Handled;
	}

	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg( 1, mapname, sizeof( mapname ) );
	if( SMC_FindMap( mapname, mapname, sizeof( mapname ) ) )
	{
		char currentid[32], newid[32];
		g_smMapList.GetString( mapname, newid, 32 );
		g_smMapList.GetString( g_cMapName, currentid, 32 );
		// check for workshop id instead of map names
		if( StrEqual(currentid, newid ))
		{
			ReplyToCommand( client, "[SMC] %t", "Can't Nominate Current Map" );
			return Plugin_Handled;
		}

		int idx = g_aOldMaps.FindString( newid );
		if( idx != -1 )
		{
			ReplyToCommand( client, "[SMC] %s %t", mapname, "Recently Played" );
			return Plugin_Handled;
		}

		ReplySource old = SetCmdReplySource( SM_REPLY_TO_CHAT );
		Nominate( client, mapname );
		SetCmdReplySource( old );
	}
	else
	{
		PrintToChatAll( "[SMC] %t", "Map was not found", mapname );
	}

	return Plugin_Handled;
}

public Action Command_UnNominate( int client, int args )
{
	if( g_cNominatedMap[client][0] == 0 )
	{
		ReplyToCommand( client, "[SMC] You haven't nominated a map" );
		return Plugin_Handled;
	}
	else
	{
		--g_iNominateCount;
		g_cNominatedMap[client][0] = 0;
		ReplyToCommand( client, "[SMC] Successfully removed nomination for '%s'", g_cNominatedMap[client] );
		return Plugin_Handled;
	}
}

public Action Command_SMap( int client, const char[] command, int argc )
{
	if ( argc < 1 )
	{
		ReplyToCommand( client, "[SM] Usage: sm_smap <map>" );

		return Plugin_Stop;
	}
	if ( !CheckCommandAccess( client, "sm_ban", ADMFLAG_CHANGEMAP, true ) )
	{
		int count = GetPlayerCount();
		if ( count > 1 )
		{
			ReplyToCommand( client, "[SM] ERROR: Cannot change map with other players on. Count: %i", count );
			return Plugin_Stop;
		}
	}

	char arg[PLATFORM_MAX_PATH];
	GetCmdArg( 1, arg, sizeof( arg ) );

	//assume that they are wanting the workshop id
	if( IsCharNumeric( arg[0] ) )
	{
		DB_FindMap( arg );
	}
	else//assume that they are wanting mapname
	{
		char mapName[PLATFORM_MAX_PATH];
		SMC_FindMap( arg, mapName, sizeof( mapName ) );
		ChangeMapDelayed( mapName );
	}


	return Plugin_Stop;
}

public Action Listener_Nextmap( int client, const char[] command, int argc )
{
	if ( client && !IsClientInGame( client ) )
	{
		return Plugin_Stop;
	}

	if ( g_cNextMap[0] == 0 )
	{
		ReplyToCommand( client, "[SMC] %t", "Pending Vote" );
	}
	else
	{
		ReplyToCommand( client, "[SMC] %t [%i]", "Next Map", g_cNextMap, Shavit_GetMapTier( g_cNextMap ) );
	}

	return Plugin_Stop;
}

public Action Command_Nextmap( int client, int args )
{
	if ( client && !IsClientInGame( client ) )
	{
		return Plugin_Handled;
	}

	if ( g_cNextMap[0] == 0 )
	{
		ReplyToCommand( client, "[SMC] %t", "Pending Vote" );
	}
	else
	{
		ReplyToCommand( client, "[SMC] %t [%i]", "Next Map", g_cNextMap, Shavit_GetMapTier( g_cNextMap ) );
	}

	return Plugin_Handled;
}

void CreateNominateMenu()
{
	delete g_hNominateMenu;
	g_hNominateMenu = new Menu( NominateMenuHandler );
	g_hNominateMenu.SetTitle( "Nominate Menu" );

	delete g_hNormalMenu;
	g_hNormalMenu = new Menu( NominateSubMenuHandler );
	g_hNormalMenu.SetTitle( "All Maps" );
	g_hNormalMenu.ExitBackButton = true;

	for(int i = 0; i < MAXTIERS; ++i)
	{
		delete g_hTiersMenu[i];
		g_hTiersMenu[i] = new Menu( NominateSubMenuHandler );
		g_hTiersMenu[i].ExitBackButton = true;
		g_hTiersMenu[i].SetTitle( "Tier %i", i );
	}

	int length = g_aMapList.Length;
	for( int i = 0; i < length; ++i )
	{
		int style = ITEMDRAW_DEFAULT;
		char mapname[PLATFORM_MAX_PATH];
		g_aMapList.GetString( i, mapname, sizeof( mapname ) );

		char currentid[32], newid[32];
		g_smMapList.GetString( mapname, newid, 32 );
		g_smMapList.GetString( g_cMapName, currentid, 32 );
		// check for workshop id instead of map names
		if( StrEqual(currentid, newid) )
		{
			style = ITEMDRAW_DISABLED;
		}

		int idx = g_aOldMaps.FindString( newid );
		if( idx != -1 )
		{
			style = ITEMDRAW_DISABLED;
		}

		char mapdisplay[PLATFORM_MAX_PATH + 32];

		int tier = Shavit_GetMapTier( mapname );

		if(g_cvMapVoteShowTier.BoolValue)
		{
			Format( mapdisplay, sizeof( mapdisplay ), "%s ( Tier %i )", mapname, tier );
		}
		else
		{
			strcopy (mapdisplay, sizeof( mapdisplay ), mapname );
		}

		g_hNormalMenu.AddItem( mapname, mapdisplay, style );
		g_hTiersMenu[tier].AddItem(  mapname, mapdisplay, style );
	}

	g_hNominateMenu.AddItem("ALL", "All Maps");

	for(int i = 0; i < MAXTIERS; ++i)
	{
		if( g_hTiersMenu[i].ItemCount > 0 )
		{
			char info[32];
			FormatEx(info, 32, "T%i", i);

			char display[32];
			FormatEx(display, 32, "Tier %i", i);

			g_hNominateMenu.AddItem(info, display);
		}
		else
		{
			delete g_hTiersMenu[i];
		}
	}
}

public int SortNominateMenu(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList list = view_as<ArrayList>(array);
	char buffer1[PLATFORM_MAX_PATH];
	char buffer2[PLATFORM_MAX_PATH];
	list.GetString(index1, buffer1, PLATFORM_MAX_PATH);
	list.GetString(index2, buffer2, PLATFORM_MAX_PATH);
	
	return strcmp(buffer1, buffer2, false);
}

void OpenNominateMenu( int client )
{
	g_hNominateMenu.Display( client, MENU_TIME_FOREVER );
}

public int NominateMenuHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( IsClientInGame( param1 ) )
		{
			char item[32];
			menu.GetItem( param2, item, sizeof( item ) );
			if( StrEqual(item, "ALL"))
			{
				g_hNormalMenu.Display(param1, MENU_TIME_FOREVER);
			}
			else
			{
				for(int i = 0; i < MAXTIERS; ++i)
				{
					char tier[32];
					FormatEx(tier, 32, "T%i", i);
					if( StrEqual( item, tier ) )
					{
						g_hTiersMenu[i].Display(param1, MENU_TIME_FOREVER);
						break;
					}
				}
			}
		}
	}
}

public int NominateSubMenuHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( IsClientInGame( param1 ) )
		{
			char mapname[PLATFORM_MAX_PATH];
			menu.GetItem( param2, mapname, sizeof( mapname ) );

			Nominate( param1, mapname );
		}
	}
	else if( action == MenuAction_Cancel && param2 == MenuCancel_ExitBack )
	{
		if( IsClientInGame( param1 ) )
		{
			g_hNominateMenu.Display( param1, MENU_TIME_FOREVER );
		}
	}
}

void Nominate( int client, const char mapname[PLATFORM_MAX_PATH] )
{
	bool found = false;

	for( int i = 0; i <= MaxClients; ++i )
	{
		if(StrEqual(mapname, g_cNominatedMap[i], false))
		{
			found = true;
			break;
		}
	}
	if( found )
	{
		ReplyToCommand( client, "[SMC] %t", "Map Already Nominated" );
		return;
	}

	g_cNominatedMap[client] = mapname;
	char name[MAX_NAME_LENGTH];
	GetClientName( client, name, sizeof( name ) );

	PrintToChatAll( "[SMC] %t", "Map Nominated", name, mapname );
}

public Action Command_RockTheVote( int client, int args )
{
	if( !IsRTVEnabled() )
	{
		ReplyToCommand( client, "[SMC] %t", "RTV Not Allowed" );
	}
	else if( g_bMapVoteStarted )
	{
		ReplyToCommand( client, "[SMC] %t", "RTV Started" );
	}
	else if( g_bRockTheVote[client] )
	{
		int total = RoundToFloor( GetPlayerCount(g_cvRTVAllowSpectators.BoolValue) * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
		if( total == 0 )
		{
			total = 1;
		}

		CheckRTV();

		int needed = total - GetRTVCount();
		if( needed != 0 )
		{
			ReplyToCommand( client, "[SMC] You have already RTVed, if you want to un-RTV use the command sm_unrtv ( %i more %s needed )", needed, ( needed == 1 ) ? "vote" : "votes" );
		}
	}
	else if( g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints( client ) <= g_cvRTVMinimumPoints.FloatValue )
	{
		ReplyToCommand( client, "[SMC] You must be a higher rank to RTV!" );
	}
	else if( GetClientTeam( client ) == CS_TEAM_SPECTATOR && !g_cvRTVAllowSpectators.BoolValue )
	{
		ReplyToCommand( client, "[SMC] Spectators have been blocked from RTVing" );
	}
	else
	{
		LeaveClient( client );
		RTVClient( client );
		CheckRTV( client );
	}

	return Plugin_Handled;
}

void CheckRTV( int client = 0 )
{
	int rtvcount = GetRTVCount();
	int total = RoundToFloor( GetPlayerCount(g_cvRTVAllowSpectators.BoolValue) * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
	if( total == 0 )
	{
		total = 1;
	}
	char name[MAX_NAME_LENGTH];

	if( client != 0 )
	{
		GetClientName( client, name, sizeof( name ) );
	}
	if( total - rtvcount > 0 )
	{
		if( client != 0 )
		{
			PrintToChatAll( "[SMC] %t", "RTV Requested", name, rtvcount, (total) );
		}
	}
	else
	{
		if( g_bMapVoteFinished )
		{
			if( client != 0 )
			{
				PrintToChatAll( "[SMC] %N wants to rock the vote! Map will now change to %s ...", client, g_cNextMap );
			}
			else
			{
				PrintToChatAll( "[SMC] RTV vote now majority, map changing to %s ...", g_cNextMap );
			}

			ChangeMapDelayed( g_cNextMap );
		}
		else
		{
			if( client != 0 )
			{
				PrintToChatAll( "[SMC] %N wants to rock the vote! Map vote will now start ...", client );
			}
			else
			{
				PrintToChatAll( "[SMC] RTV vote now majority, map vote starting ..." );
			}

			InitiateMapVote( MapChange_Instant );
		}
	}
}

public Action Command_UnRockTheVote( int client, int args )
{
	if( !IsRTVEnabled() )
	{
		ReplyToCommand( client, "[SMC] RTV has not been enabled yet" );
	}
	else if( g_bMapVoteStarted || g_bMapVoteFinished )
	{
		ReplyToCommand( client, "[SMC] Map vote already %s", ( g_bMapVoteStarted ) ? "initiated" : "finished" );
	}
	else if( g_bRockTheVote[client] )
	{
		UnRTVClient( client );

		int total = RoundToFloor( GetPlayerCount( g_cvRTVAllowSpectators.BoolValue) * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
		if( total == 0 )
		{
			total = 1;
		}
		int needed = total - GetRTVCount();
		if( needed > 0 )
		{
			PrintToChatAll( "[SMC] %N no longer wants to rock the vote! ( %i more votes needed )", client, needed );
		}
	}

	return Plugin_Handled;
}

public Action Command_Stay( int client, int args )
{
	if( g_bStay[client] )
	{
		ReplyToCommand( client, "[SMC] You have already voted to stay on the current map" );
	}
	else
	{
		StayClient( client );
		UnRTVClient( client );

		if( g_bMapVoteStarted )
		{
			int total = RoundToFloor( GetPlayerCount( g_cvRTVAllowSpectators.BoolValue) * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
			if( total == 0 )
			{
				total = 1;
			}
			int needed = total - GetRTVCount();
			if( needed > 0 )
			{
				CancelVote();
				g_bMapVoteStarted = false;
			}
		}
		ReplyToCommand( client, "[SMC] You have voted to stay on the current map" );
	}

	return Plugin_Handled;
}

public Action Command_Leave( int client, int args )
{
	if( g_bStay[client] )
	{
		LeaveClient( client );
		ReplyToCommand( client, "[SMC] You have removed your vote to stay on the current map" );
	}
	else
	{
		ReplyToCommand( client, "[SMC] You haven't voted to stay on the current map yet" );
	}

	return Plugin_Handled;
}

#if defined DEBUG
public Action Command_Debug( int client, int args )
{
	g_bDebug = !g_bDebug;
	ReplyToCommand( client, "[SMC] Debug mode: %s", g_bDebug ? "ENABLED" : "DISABLED" );

	return Plugin_Handled;
}
#endif

void RTVClient( int client )
{
	g_bRockTheVote[client] = true;
	Call_StartForward( g_hForward_OnRTV );
	Call_PushCell( client );
	Call_Finish();
}

void UnRTVClient( int client )
{
	g_bRockTheVote[client] = false;
	Call_StartForward( g_hForward_OnUnRTV );
	Call_PushCell( client );
	Call_Finish();
}

void StayClient( int client )
{
	g_bStay[client] = true;
	Call_StartForward( g_hForward_OnStay );
	Call_PushCell( client );
	Call_Finish();
}

void LeaveClient( int client )
{
	g_bStay[client] = false;
	Call_StartForward( g_hForward_OnLeave );
	Call_PushCell( client );
	Call_Finish();
}

/* Stocks */
stock void SQL_SetPrefix()
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, sFile, sizeof( sFile ), "configs/shavit-prefix.txt" );

	File fFile = OpenFile( sFile, "r" );
	if( fFile == null )
	{
		SetFailState( "Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it." );
	}

	char sLine[PLATFORM_MAX_PATH*2];
	while( fFile.ReadLine( sLine, sizeof( sLine ) ) )
	{
		TrimString( sLine );
		strcopy( g_cSQLPrefix, sizeof( g_cSQLPrefix ), sLine );

		break;
	}

	delete fFile;
}

stock void RemoveString( ArrayList array, const char[] target )
{
	int idx = array.FindString( target );
	if( idx != -1 )
	{
		array.Erase( idx );
	}
}

stock bool LoadFromMapsFolder( ArrayList list )
{
	//from yakmans maplister plugin
	DirectoryListing mapdir = OpenDirectory( "maps/" );
	if( mapdir == null )
		return false;

	char name[PLATFORM_MAX_PATH];
	FileType filetype;
	int namelen;

	while( mapdir.GetNext( name, sizeof( name ), filetype ) )
	{
		if( filetype != FileType_File )
			continue;

		namelen = strlen( name ) - 4;
		if( StrContains( name, ".bsp", false ) != namelen )
			continue;

		name[namelen] = '\0';

		list.PushString( name );
	}

	delete mapdir;

	return true;
}

stock void ChangeMapDelayed( const char[] map, float delay = 2.0 )
{
	int playerCount = GetPlayerCount( g_cvRTVAllowSpectators.BoolValue );
	if( playerCount > 0 )
	{
		Set_NextMap( map );
		FindConVar( "mp_roundtime" ).IntValue = 0;
		FindConVar( "mp_timelimit" ).IntValue = 0;
		char message[256];
		int rtvcount = GetRTVCount();
		int total = RoundToFloor( playerCount * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
		if( total == 0 )
		{
			total = 1;
		}
		int needed = total - rtvcount;
		FormatEx(message, 256, "MESSAGE: Changing map playercount: %i, rtvcount: %i, total: %i, needed: %i ", playerCount, rtvcount, total, needed);
		LogError(message);

		CS_TerminateRound( ( 0.1 ), CSRoundEnd_Draw );
		CreateTimer( delay, Timer_ChangeMap );
	}
	else
	{
		char message[256];
		int rtvcount = GetRTVCount();
		int total = RoundToFloor( playerCount * ( g_cvRTVRequiredPercentage.FloatValue / 100 ) );
		if( total == 0 )
		{
			total = 1;
		}
		int needed = total - rtvcount;
		FormatEx(message, 256, "ERROR: Tried to change map with 0 people on. playercount: %i, rtvcount: %i, total: %i, needed: %i ", playerCount, rtvcount, total, needed);
		LogError(message);
	}
}

stock int GetRTVCount()
{
	int rtvcount = 0;
	for( int i = 1; i <= MaxClients; ++i )
	{
		if( IsClientInGame( i ) )
		{
			// dont count players that can't vote
			if( !g_cvRTVAllowSpectators.BoolValue && IsClientObserver( i ) )
			{
				continue;
			}

			if( g_bRockTheVote[i] )
			{
				++rtvcount;
			}
			else if( g_bStay[i] )
			{
				--rtvcount;
			}
		}
	}

	if( rtvcount < 0 )
	{
		rtvcount = 0;
	}

	return rtvcount;
}

stock void DebugPrint( const char[] message, any ... )
{
	#if defined DEBUG
	PrintToServer( message );
	#endif
}

stock void GetMapName( char[] buffer, int size, bool current = false )
{
	if( current )
	{
		GetCurrentMap( buffer, size );
	}

	GetMapDisplayName( buffer, buffer, size );

	for( int i = 0; i < size; ++i )
	{
		if( IsCharUpper( buffer[i] ) )
		{
			buffer[i] = CharToLower( buffer[i] );
		}
	}
}

stock void Set_NextMap( const char[] map )
{
	PrintToConsoleAll("Nextmap Set: %s", map);
	strcopy( g_cNextMap, sizeof( g_cNextMap ), map );
}

public int Native_GetNextMap( Handle handler, int numParams )
{
	SetNativeString(1, g_cNextMap, GetNativeCell(2));

	char id[PLATFORM_MAX_PATH];
	g_smMapList.GetString( g_cNextMap, id, sizeof( id ) );

	SetNativeString(3, id, GetNativeCell(4));
	return 0;
}

// native bool SMC_SetNextMap(const char[] mapName, int mapLength);
public any Native_SetNextMap(Handle plugin, int numParams)
{
	char buffer[PLATFORM_MAX_PATH];
	int length = GetNativeCell(2);
	// int bytes;
	if(GetNativeString(1, buffer, length) != SP_ERROR_NONE)
	{
		return false;
	}

	char map[PLATFORM_MAX_PATH];

	if(!SMC_FindMap(buffer, map, PLATFORM_MAX_PATH))
	{
		return false;
	}

	Set_NextMap(map);

	return true;
}

// native bool SMC_ChangeMap(const char[] mapName, int mapLength, float delay = 2.0);
public any Native_ChangeMap(Handle plugin, int numParams)
{
	char buffer[PLATFORM_MAX_PATH];
	int length = GetNativeCell(2);
	float delay = GetNativeCell(3);
	// int bytes;
	if(GetNativeString(1, buffer, length) != SP_ERROR_NONE)
	{
		return false;
	}

	char map[PLATFORM_MAX_PATH];

	if(!SMC_FindMap(buffer, map, PLATFORM_MAX_PATH))
	{
		return false;
	}

	ChangeMapDelayed(map, delay);

	return true;
}


void DB_FindMap( char[] id )
{
	char buffer[512];
	
	FormatEx( buffer, sizeof( buffer ), "SELECT WorkshopID, Map FROM db_maplist WHERE WorkshopID = '%s' ORDER BY Map ASC LIMIT 1", id );
	g_hDatabase.Query( FindMapCallback, buffer, _, DBPrio_Low );
}

public void FindMapCallback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SMC] - ( FindMapCallback ) - %s", error );
		return;
	}

	if(results.FetchRow())
	{
		char map[PLATFORM_MAX_PATH];
		char id[32];

		results.FetchString( 0, id, sizeof( id ) );
		results.FetchString( 1, map, sizeof( map ) );

		g_smMapList.SetString( map, id, true );//ensure that the map is in the maplist properly
		

		PrintToChatAll( "[SMC] Force Changing Map To: %s", map );
		LogMessage( "[SMC] Force Changing Map To: %s", map );

		ChangeMapDelayed( map );
	}
	else
	{
		LogError( "[SMC] - ( FindMapCallback ) - Failed to fetch results" );
	}
}

int GetPlayerCount(bool includeSpec = true)
{
	int count = 0;
	for( int i = 1; i <= MaxClients; ++i )
	{
		if( IsClientInGame( i ) )
		{
			if( ( includeSpec && IsClientObserver( i ) ) || IsFakeClient( i ) || IsClientSourceTV( i ) || IsClientReplay( i ) )
			{
				continue;
			}

			++count;
		}
	}
	return count;
}