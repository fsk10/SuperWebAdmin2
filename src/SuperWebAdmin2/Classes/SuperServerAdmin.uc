class SuperServerAdmin expands Object;

var SuperServerAdminSpectator Spectator;
var UTServerAdminSpectator Spectator2;

var string Path;

var int ListenPort;
var bool bListen;

var SWAServer WebServer;

//config actors
var OPBanConfig	opconf;
var SWAConfig Config;

var LevelInfo Level;

// Main opban actor...
var OPBan opmain;

var	ListItem GameTypeList;

var ListItem IncludeMaps;
var ListItem ExcludeMaps;

var ListItem IncludeMutators;
var ListItem ExcludeMutators;
var ListItem OtherMutators;
var string URLMutators;
var ListItem AvailMutators;     // all mutators of the .int files, sorted by name
var string ActiveMutators;      // ordered mutator list for the next map (see LoadMutators)
var string JustMovedMutators;   // keeps moved items selected on the Mutators page
const MaxMutatorClasses = 1000;
const SWAVersion = "1.0";

var string MenuPage;
var string RootPage;

var string WelcomePage;
var string BlankPage;

var string CurrentPage;
var string CurrentMenuPage;
var string CurrentIndexPage;
var string CurrentPlayersPage;
var string CurrentGamePage;
var string CurrentConsolePage;
var string CurrentConsoleLogPage;
var string CurrentConsoleSendPage;
var string CurrentMutatorsPage;
var string CurrentRestartPage;
var string CurrentRulesPage;
var string CurrentQuickSetPage;

var string DefaultsPage;
var string DefaultsMenuPage;
var string DefaultsMapsPage;
var string DefaultsRulesPage;
var string DefaultsSettingsPage;
var string DefaultsBotsPage;
var string DefaultsIPPolicyPage;
var string DefaultsRestartPage;

var string DefaultsChangePasswordPage;

var string SuperAdminPage;
var string SuperAdminMenuPage;
var string SuperAdminServerPage;
var string SuperAdminWebAdminPage;
var string SuperAdminRestartPage;
var string SuperAdminQuickSetConfigPage;
var string OPBanList;
var string DynaList;
var string OPBanOptions;
var string EditOPList;
var string EditUTList;
var string EditDynaList;

var string MessageUHTM;

var string DefaultClass;
var string HighlightedClass;

//var string WhoIsNick;

var bool ActorsChecked;
var bool OPBanEnabled;
var bool bBTScores;
var Actor IpToCountry;
var bool bIpToCountry;

var bool bTournament;

var SWARequest CurRequest;   // the request being answered (pages are built synchronously)

// Failed logins per IP (brute force protection)
var string AuthFailIP[16];
var int AuthFailCount[16];
var float AuthFailTime[16];
const MaxAuthFailures = 5;
const AuthLockSeconds = 60;

//var string ServerURL;
// Store to hold which ban range page is showing
var int		BanPage;
var int		DynaPage;

function Cleanup(); //this function is triggered when the server class is destroyed

function string GetPortStr()
{
	local int i,count;
	local string PortStr;
	if(!bListen)
		return "None    ";
	PortStr=string(ListenPort);
	count=len(PortStr);
	for(i=0;i<(8-count);i++)
		PortStr=PortStr$" ";
	return PortStr;
}

event Init()
{
	local OPBan opb;
	local int i, temp;
	local string Pass;

	if(Config == None)
	{
		log("SuperWebAdmin: I have to be spawned by SuperWebAdmin2.SWAServer !!! Check the installation notes !!!");
	}

	log("+=============================+");
	log("|     SuperWebAdmin2 "$SWAVersion$"      |");
	log("| based on SWA 0.97b by Rush  |");
	log("|    Running at port: "$GetPortStr()$"|");
	log("+-----------------------------+");
	if(!bListen)
		log("SWA: Could not bind the port for listening, you may lack privileges or just the value is incorrect.");

	//used for md5 passwords
	if(Config.Salt == "" || len(Config.Salt) < 10)
	{
		Config.Salt = Config.randomHash();
		Config.SaveConfig();
	}
	for(i=0;i<50;i++)
	{
		if(Config.Userlist[i]!= "")
		{
			Pass = Config.SelElem(Config.Userlist[i], 2);
			if (Pass == "")
				log("SWA: Warning, account "$Config.SelElem(Config.Userlist[i], 1)$" has no password and is locked until one is set.");
			else if (!Config.IsMD5Hash(Pass))
			{
				log("SWA: Converting password for user "$Config.SelElem(Config.Userlist[i], 1)$" to MD5");
				Config.ChangePassword(Config.SelElem(Config.Userlist[i], 1), Pass, true);
			}
		}
	}

	Spectator = Level.Spawn(class'SuperServerAdminSpectator');
	Spectator2 = Level.Spawn(class'UTServerAdminSpectator');

	Spectator.SWA=self;
	Spectator.bAdmin=True;
	Spectator.PlayerReplicationInfo.bAdmin=True;

	OPBanEnabled=Config.bOPBanEnabled;

	foreach Level.AllActors(class'OPBan', opb)
	{
		if (String(opb.Class) == "OPBan.OPBan")
		{
			log("SWA: External OPBan is already spawned ! You have to disable it.");
			OPBanEnabled=False;
		}
	}

	// Find our root class so we can then find the config class...
	if(OPBanEnabled)
	{
		log("SWA: Spawning OPBan ...");
		Level.Spawn(class'OPBan');
		foreach Level.AllActors(class'OPBan', opb)
		{
			if (String(opb.Class) == "SuperWebAdmin2.OPBan")
			{
				opconf = opb.opconf;
				opmain = opb;
			}
		}
	}
	if(Left(string(Level), 3)=="BT-" || Left(string(Level), 7)=="CTF-BT-")
	{
		bBTScores=True;
	}

	LoadGameTypes();
	LoadMutators();

	if(DeathMatchPlus(Level.Game) != None && DeathMatchPlus(Level.Game).bTournament)
		bTournament=True;
}


function LoadGameTypes()
{
	// Game types register in their .int with MetaClass TournamentGameInfo (Botpack) or
	// Engine.GameInfo (e.g. NewCTF). SWA 0.97 read only the first, so NewCTF was missing.
	GameTypeList = None;
	AddGameTypes("TournamentGameInfo");
	AddGameTypes("Engine.GameInfo");
	AddGameType(string(Level.Game.Class));
}

function AddGameTypes(string MetaClass)
{
	local string NextGame;
	local int i;

	NextGame = Level.GetNextInt(MetaClass, 0);
	while (NextGame != "" && i < 200)
	{
		AddGameType(NextGame);
		NextGame = Level.GetNextInt(MetaClass, ++i);
	}
}

function AddGameType(string GameClassName)
{
	local class<GameInfo> TempClass;
	local ListItem TempItem;

	if (GameTypeList != None && GameTypeList.FindItem(GameClassName) != None)
		return;
	TempClass = class<GameInfo>(DynamicLoadObject(GameClassName, class'Class', true));
	if (TempClass == None)
		return;
	TempItem = new(None) class'ListItem';
	TempItem.Tag = TempClass.Default.GameName;
	if (TempItem.Tag == "")
		TempItem.Tag = GameClassName;
	TempItem.Data = string(TempClass);
	if (GameTypeList == None)
		GameTypeList = TempItem;
	else
		GameTypeList.AddElement(TempItem);
}

//-----------------------------------------------------------------------------
// Mutators and the travel URL (SWA2)
//
// ActiveMutators is the ordered, comma separated list of mutators the next map gets.
// It starts as the ?mutator= option of the URL the current map was started with, NOT
// the live BaseMutator chain: mutators spawn other mutators (IG+ adds PureClickBoard and
// IGPlus_HitFeedback, server actors add SmartCTF), and those must not end up in the URL.
// IncludeMutators/ExcludeMutators (the two lists of the Mutators page) and URLMutators
// ("Other Mutators": active mutators without an .int entry) are derived from it.
//-----------------------------------------------------------------------------

function LoadMutators()
{
	local int i, k;
	local string NextMutator, NextDesc;
	local ListItem TempItem;

	AvailMutators = None;
	Level.GetNextIntDesc("Engine.Mutator", 0, NextMutator, NextDesc);
	while (NextMutator != "" && i < MaxMutatorClasses)
	{
		if (AvailMutators == None || AvailMutators.FindItem(NextMutator) == None)
		{
			TempItem = new(None) class'ListItem';
			k = InStr(NextDesc, ",");
			if (k == -1)
				TempItem.Tag = NextDesc;
			else
				TempItem.Tag = Left(NextDesc, k);
			if (TempItem.Tag == "")
				TempItem.Tag = NextMutator;
			TempItem.Data = NextMutator;
			if (AvailMutators == None)
				AvailMutators = TempItem;
			else
				AvailMutators.AddSortedElement(AvailMutators, TempItem);
		}
		i++;
		Level.GetNextIntDesc("Engine.Mutator", i, NextMutator, NextDesc);
	}
	if (NextMutator != "")
		log("SWA: More than "$MaxMutatorClasses$" mutators in the .int files, the list is truncated.");

	ActiveMutators = "";
	AddMutatorsFromString(GetURLOption(Level.GetLocalURL(), "mutator"), false);
	RebuildMutatorLists();
}

// Rebuilds the page lists from ActiveMutators. Included mutators keep the active order,
// excluded ones are sorted by name.
function RebuildMutatorLists()
{
	local string Rest, Item;
	local ListItem Avail, TempItem;

	IncludeMutators = None;
	ExcludeMutators = None;
	OtherMutators = None;
	URLMutators = "";

	Rest = ActiveMutators;
	while (NextListElem(Rest, Item))
	{
		Avail = FindAvailMutator(Item);
		if (Avail == None)
		{
			URLMutators = ListAppend(URLMutators, Item);
			continue;
		}
		TempItem = CopyMutatorItem(Avail);
		if (IncludeMutators == None)
			IncludeMutators = TempItem;
		else
			IncludeMutators.AddElement(TempItem);
	}

	for (Avail = AvailMutators; Avail != None; Avail = Avail.Next)
	{
		if (ListContains(ActiveMutators, Avail.Data))
			continue;
		TempItem = CopyMutatorItem(Avail);
		if (ExcludeMutators == None)
			ExcludeMutators = TempItem;
		else
			ExcludeMutators.AddElement(TempItem);
	}
	JustMovedMutators = "";
}

function ListItem CopyMutatorItem(ListItem Src)
{
	local ListItem TempItem;

	TempItem = new(None) class'ListItem';
	TempItem.Tag = Src.Tag;
	TempItem.Data = Src.Data;
	TempItem.bJustMoved = ListContains(JustMovedMutators, Src.Data);
	return TempItem;
}

function ListItem FindAvailMutator(string MutatorClass)
{
	if (AvailMutators == None)
		return None;
	return AvailMutators.FindItem(MutatorClass);
}

// Adds the comma separated mutators in Str to ActiveMutators (skipping duplicates).
// With bValidate, only names that load as a Mutator class are accepted.
function AddMutatorsFromString(string Str, bool bValidate)
{
	local string Rest, Item;

	Rest = Str;
	while (NextListElem(Rest, Item))
	{
		if (ListContains(ActiveMutators, Item))
			continue;
		if (bValidate && !IsValidMutatorClass(Item))
		{
			log("SWA: Ignoring unknown mutator class '"$Item$"'.");
			continue;
		}
		ActiveMutators = ListAppend(ActiveMutators, Item);
	}
}

function bool IsValidMutatorClass(string MutatorClass)
{
	if (!IsSafeClassName(MutatorClass))
		return false;
	if (FindAvailMutator(MutatorClass) != None)
		return true;
	return class<Mutator>(DynamicLoadObject(MutatorClass, class'Class', true)) != None;
}

// Package.Class with only letters, digits, '_' and '-': nothing that can break the URL.
function bool IsSafeClassName(string S)
{
	local int i, Dot;
	local string C;

	if (S == "" || Len(S) > 128)
		return false;
	Dot = InStr(S, ".");
	if (Dot <= 0 || Dot == Len(S) - 1)
		return false;
	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if (C == ".")
		{
			if (i != Dot)
				return false;
		}
		else if (!((C >= "a" && C <= "z") || (C >= "A" && C <= "Z") || (C >= "0" && C <= "9") || C == "_" || C == "-"))
			return false;
	}
	return true;
}

// Called by the "Other Mutators" field: replaces the active mutators that have no .int entry.
function UpdateURLMutators(string Str)
{
	local string Rest, Item, Kept;

	Rest = ActiveMutators;
	while (NextListElem(Rest, Item))
		if (FindAvailMutator(Item) != None)
			Kept = ListAppend(Kept, Item);
	ActiveMutators = Kept;
	AddMutatorsFromString(Str, true);
	RebuildMutatorLists();
}

function String UsedMutators()
{
	return ActiveMutators;
}

// New Mutators page: the ticked .int mutators (kept in their current order, new ones
// appended) plus the "Other mutators" field (mutators without .int entry).
function SetMutatorsFromForm(SWARequest Request)
{
	local int i, Count;
	local string Checked, Others, NewList, Rest, Item;
	local ListItem Avail;

	Count = Request.GetVariableCount("Mutator");
	for (i = 0; i < Count; i++)
	{
		Avail = FindAvailMutator(Request.GetVariableNumber("Mutator", i));
		if (Avail != None && !ListContains(Checked, Avail.Data))
			Checked = ListAppend(Checked, Avail.Data);
	}
	// "Other mutators" field: classes without .int entry
	Rest = Request.GetVariable("OtherMutators", "");
	while (NextListElem(Rest, Item))
	{
		if (FindAvailMutator(Item) != None)
			Checked = ListAppend(Checked, FindAvailMutator(Item).Data);
		else if (!ListContains(Others, Item) && IsValidMutatorClass(Item))
			Others = ListAppend(Others, Item);
		else if (!ListContains(Others, Item))
			log("SWA: Ignoring unknown mutator class '"$Item$"'.");
	}
	// existing entries keep their position, new ones are appended
	Rest = ActiveMutators;
	while (NextListElem(Rest, Item))
	{
		if (FindAvailMutator(Item) != None)
		{
			if (ListContains(Checked, Item))
				NewList = ListAppend(NewList, Item);
		}
		else if (ListContains(Others, Item))
			NewList = ListAppend(NewList, Item);
	}
	Rest = Checked;
	while (NextListElem(Rest, Item))
		if (!ListContains(NewList, Item))
			NewList = ListAppend(NewList, Item);
	Rest = Others;
	while (NextListElem(Rest, Item))
		if (!ListContains(NewList, Item))
			NewList = ListAppend(NewList, Item);
	ActiveMutators = NewList;
}

// <option>s for the two lists of the Mutators page: the mutators of the next map in
// their order (bUsed), or the other .int mutators.
function string GenerateMutatorOptions(bool bUsed)
{
	local ListItem M;
	local string S, Rest, Item;

	if (bUsed)
	{
		Rest = ActiveMutators;
		while (NextListElem(Rest, Item))
		{
			M = FindAvailMutator(Item);
			if (M != None)
				S = S$MutatorOption(M);
		}
		return S;
	}
	for (M = AvailMutators; M != None; M = M.Next)
		if (!ListContains(ActiveMutators, M.Data))
			S = S$MutatorOption(M);
	return S;
}

function string MutatorOption(ListItem M)
{
	local string Tag;

	Tag = M.Tag;
	if (Tag == "" || Tag ~= M.Data)
		return "<option value=\""$FixHTML(M.Data)$"\" title=\""$FixHTML(M.Data)$"\">"$FixHTML(M.Data)$"</option>";
	return "<option value=\""$FixHTML(M.Data)$"\" data-tag=\""$FixHTML(Tag)$"\" data-cls=\""$FixHTML(M.Data)$"\" title=\""$FixHTML(Tag)$" ("$FixHTML(M.Data)$")\">"
		$FixHTML(Tag)$" ("$FixHTML(M.Data)$")</option>";
}

function string GenerateActiveOrder()
{
	local string S, Rest, Item;
	local ListItem M;

	Rest = ActiveMutators;
	while (NextListElem(Rest, Item))
	{
		M = FindAvailMutator(Item);
		if (M != None)
			S = S$"<li>"$FixHTML(M.Tag)$"<span class=\"cls\">"$FixHTML(Item)$"</span></li>";
		else
			S = S$"<li>"$FixHTML(Item)$"<span class=\"cls\">no .int entry</span></li>";
	}
	if (S == "")
		return "<p class=\"muted\">No mutators.</p>";
	return "<ol class=\"order\">"$S$"</ol>";
}

function int CountAvailMutators()
{
	local ListItem M;
	local int n;

	for (M = AvailMutators; M != None; M = M.Next)
		n++;
	return n;
}

function String GenerateMutatorListSelect(ListItem MutatorList)
{
	local ListItem TempItem;
	local String ResponseStr, SelectedStr;

	if (MutatorList == None)
		return "<option value=\"\">*** None ***</option>";

	for (TempItem = MutatorList; TempItem != None; TempItem = TempItem.Next) {
		SelectedStr = "";
		if (TempItem.bJustMoved) {
			SelectedStr = " selected";
			TempItem.bJustMoved=false;
		}
		ResponseStr = ResponseStr$"<option value=\""$FixHTML(TempItem.Data)$"\""$SelectedStr$">"$FixHTML(TempItem.Tag)$"</option>";
	}
	return ResponseStr;
}

//-----------------------------------------------------------------------------
// Comma separated list helpers (no element limit, case-insensitive, spaces trimmed)
//-----------------------------------------------------------------------------

// Pops the next non-empty element of Rest into Item. Returns false at the end.
function bool NextListElem(out string Rest, out string Item)
{
	local int k;

	while (Rest != "")
	{
		k = InStr(Rest, ",");
		if (k == -1)
		{
			Item = Rest;
			Rest = "";
		}
		else
		{
			Item = Left(Rest, k);
			Rest = Mid(Rest, k + 1);
		}
		Item = TrimSpaces(Item);
		if (Item != "")
			return true;
	}
	Item = "";
	return false;
}

function bool ListContains(string List, string Item)
{
	local string Rest, Elem;

	Rest = List;
	while (NextListElem(Rest, Elem))
		if (Elem ~= Item)
			return true;
	return false;
}

function string ListAppend(string List, string Item)
{
	if (List == "")
		return Item;
	return List$","$Item;
}

function string ListRemove(string List, string Item)
{
	local string Rest, Elem, Result;

	Rest = List;
	while (NextListElem(Rest, Elem))
		if (!(Elem ~= Item))
			Result = ListAppend(Result, Elem);
	return Result;
}

function string TrimSpaces(string S)
{
	while (Left(S, 1) == " ")
		S = Mid(S, 1);
	while (Right(S, 1) == " ")
		S = Left(S, Len(S) - 1);
	return S;
}

//-----------------------------------------------------------------------------
// URL options and the travel URL
//-----------------------------------------------------------------------------

// Value of ?Key=value in URL (key case-insensitive), "" when missing. Handles the
// option being the last one and options without a value.
function string GetURLOption(string URL, string Key)
{
	local string Rest, Opt;
	local int k;

	k = InStr(URL, "?");
	if (k == -1)
		return "";
	Rest = Mid(URL, k + 1);
	while (Rest != "")
	{
		k = InStr(Rest, "?");
		if (k == -1)
		{
			Opt = Rest;
			Rest = "";
		}
		else
		{
			Opt = Left(Rest, k);
			Rest = Mid(Rest, k + 1);
		}
		k = InStr(Opt, "=");
		if (k == -1)
		{
			if (Opt ~= Key)
				return "";
		}
		else if (Left(Opt, k) ~= Key)
			return Mid(Opt, k + 1);
	}
	return "";
}

// Options the engine adds for the (non-existent) local player; they are not game options.
function bool IsPlayerURLOption(string Key)
{
	return Left(Key, 1) == "*" || Key ~= "Name" || Key ~= "Class" || Key ~= "Team" || Key ~= "Skin"
		|| Key ~= "Face" || Key ~= "Voice" || Key ~= "OverrideClass" || Key ~= "Password";
}

// Map?game=Game?mutator=Mutators plus every other game option the current map was started
// with (e.g. ?IGPlusSettings=, ?Tickrate=), so a map switch changes only map/game/mutators.
function string BuildTravelURL(string Map, string Game, string Mutators)
{
	local string URL, Rest, Opt, Key;
	local int k;

	URL = Map$"?game="$Game;
	if (Mutators != "")
		URL = URL$"?mutator="$Mutators;

	Rest = Level.GetLocalURL();
	k = InStr(Rest, "?");
	if (k == -1)
		return URL;
	Rest = Mid(Rest, k + 1);
	while (Rest != "")
	{
		k = InStr(Rest, "?");
		if (k == -1)
		{
			Opt = Rest;
			Rest = "";
		}
		else
		{
			Opt = Left(Rest, k);
			Rest = Mid(Rest, k + 1);
		}
		k = InStr(Opt, "=");
		if (k == -1)
			Key = Opt;
		else
			Key = Left(Opt, k);
		if (Key == "" || Key ~= "game" || Key ~= "mutator" || IsPlayerURLOption(Key))
			continue;
		URL = URL$"?"$Opt;
	}
	return URL;
}

// The map name as used in the travel URL, if it is a map of GameType on this server.
// Accepts "CTF-Foo" and "CTF-Foo.unr" (c00lbot sends the latter). Returns "" otherwise.
function string ValidateMap(string Map, string GameType)
{
	local ListItem Maps, Found;

	if (Map == "" || InStr(Map, "?") != -1 || InStr(Map, "#") != -1)
		return "";
	if (!(Right(Map, 4) ~= ".unr"))
		Map = Map$".unr";
	ReloadExcludeMaps(Maps, GameType);
	if (Maps == None)
		return "";
	Found = Maps.FindItem(Map);
	if (Found == None)
		return "";
	return Found.Data;
}

// GameType if it is one of the game types offered by this server, "" otherwise.
function string ValidateGameType(string GameType)
{
	local ListItem Found;

	if (GameType ~= string(Level.Game.Class))
		return string(Level.Game.Class);
	if (GameTypeList == None || !IsSafeClassName(GameType))
		return "";
	Found = GameTypeList.FindItem(GameType);
	if (Found == None)
		return "";
	return Found.Data;
}

function String PadLeft(String InStr, int Width, String PadStr)
{
	local String OutStr;

	if (Len(PadStr) == 0)
		PadStr = " ";

	for (OutStr=InStr; Len(OutStr) < Width; OutStr=PadStr$OutStr);

	return Right(OutStr, Width); // in case PadStr is more than one character
}

function ApplyMapList(out ListItem ExcludeMaps, out ListItem IncludeMaps, String GameType, String MapListType)
{
	local class<MapList> MapListClass;
	local ListItem TempItem;
	local int IncludeCount, i;

	MapListClass = Class<MapList>(DynamicLoadObject(MapListType, class'Class'));

	IncludeMaps = None;
	ReloadExcludeMaps(ExcludeMaps, GameType);

	IncludeCount = ArrayCount(MapListClass.Default.Maps);
	for(i=0;i<IncludeCount;i++)
	{
		if(MapListClass.Default.Maps[i] == "")
			break;
		if (ExcludeMaps != None)
		{
			TempItem = ExcludeMaps.DeleteElement(ExcludeMaps, MapListClass.Default.Maps[i]);

			if(TempItem != None)
			{
				if (IncludeMaps == None)
					IncludeMaps = TempItem;
				else
					IncludeMaps.AddElement(TempItem);
			}
			else
				Log("SWA: Unknown map in Map List: "$MapListClass.Default.Maps[i]);
		}
		else
			Log("SWA: Empty exclude list, i="$i);
	}
}

function ReloadExcludeMaps(out ListItem ExcludeMaps, String GameType)
{
	local class<GameInfo>	GameClass;
	local string FirstMap, NextMap, TestMap, MapName;
	local ListItem TempItem;

	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));

	ExcludeMaps = None;
	if(GameClass.Default.MapPrefix == "")
		return;
	FirstMap = Level.GetMapName(GameClass.Default.MapPrefix, "", 0);
	NextMap = FirstMap;
	while (!(FirstMap ~= TestMap) && FirstMap != "")
	{
		// Add the map.
		TempItem = new(None) class'ListItem';
		TempItem.Data = NextMap;

		if(Right(NextMap, 4) ~= ".unr")
			TempItem.Tag = Left(NextMap, Len(NextMap) - 4);
		else
			TempItem.Tag = NextMap;

		if (ExcludeMaps == None)
			ExcludeMaps = TempItem;
		else
			ExcludeMaps.AddSortedElement(ExcludeMaps, TempItem);

		NextMap = Level.GetMapName(GameClass.Default.MapPrefix, NextMap, 1);
		TestMap = NextMap;
	}
}

function ReloadIncludeMaps(out ListItem ExcludeMaps, out ListItem IncludeMaps, String GameType)
{
	local class<GameInfo> GameClass;
	local ListItem TempItem;
	local int i;

	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));
	if(GameClass.Default.MapListType == None)
		return;
	if (GameClass != None)
	{
		for (i=0; i<ArrayCount(GameClass.Default.MapListType.Default.Maps) && GameClass.Default.MapListType.Default.Maps[i] != ""; i++)
		{
			// Add the map.
			TempItem = ExcludeMaps.DeleteElement(ExcludeMaps, GameClass.Default.MapListType.Default.Maps[i]);
			if (TempItem == None)
			{
				TempItem = new(None) class'ListItem';
				TempItem.Data = GameClass.Default.MapListType.Default.Maps[i];

				if(Right(TempItem.Data, 4) ~= ".unr")
					TempItem.Tag = Left(TempItem.Data, Len(TempItem.Data) - 4);
				else
					TempItem.Tag = TempItem.Data;
			}
			else
			{
				if (IncludeMaps == None)
					IncludeMaps = TempItem;
				else
					IncludeMaps.AddElement(TempItem);
			}
		}
	}
}

function UpdateDefaultMaps(String GameType, ListItem TempItem)
{
	local class<GameInfo> GameClass;
	local int i;

	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));

	for (i=0; i<ArrayCount(GameClass.Default.MapListType.Default.Maps); i++)
	{
		if (TempItem != None)
		{
			GameClass.Default.MapListType.Default.Maps[i] = TempItem.Data;
			TempItem = TempItem.Next;
		}
		else
			GameClass.Default.MapListType.Default.Maps[i] = "";
	}

	GameClass.Static.StaticSaveConfig();
}

function String GenerateGameTypeOptions(String CurrentGameType)
{
	local ListItem TempItem;
	local String SelectedStr, OptionStr;

	for (TempItem = GameTypeList; TempItem != None; TempItem = TempItem.Next)
	{
		if (CurrentGameType ~= TempItem.Data)
			SelectedStr = " selected";
		else
			SelectedStr = "";

		OptionStr = OptionStr$"<option value=\""$TempItem.Data$"\""$SelectedStr$">"$TempItem.Tag$"</option>";
	}
	return OptionStr;
}

function String GenerateQuickSetOptions()
{
	local String OptionStr;
	local int i;

	for (i=0;i<20;i++)
	{
	if(Config.SelElem(Config.QuickSetConf[i], 1)=="")
		continue;
	OptionStr = OptionStr$"<option value=\""$i$"\">"$Config.SelElem(Config.QuickSetConf[i], 1)$"</option>";

	}
	return OptionStr;
}

function String GenerateMapListOptions(String GameType, String MapListType)
{
	local class<GameInfo> GameClass;
	local String DefaultBaseClass, NextDefault, NextDesc, SelectedStr, OptionStr;
	local int NumDefaultClasses;

	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));
	if(GameClass == None)
		return "";

	DefaultBaseClass = String(GameClass.Default.MapListType);

	if(DefaultBaseClass == "")
		return "";

	NextDefault = "Custom";
	NextDesc = "Custom";

	if(DynamicLoadObject(DefaultBaseClass, class'Class') == None)
		return "";
	while( (NextDefault != "") && (NumDefaultClasses < 50) )
	{
		if (MapListType ~= NextDefault)
			SelectedStr = " selected";
		else
			SelectedStr = "";

		OptionStr = OptionStr$"<option value=\""$NextDefault$"\""$SelectedStr$">"$NextDesc$"</option>";

		Level.GetNextIntDesc(DefaultBaseClass, NumDefaultClasses++, NextDefault, NextDesc);
	}
	return OptionStr;
}

function String GenerateMapListSelect(ListItem MapList, optional string SelectedItem)
{
	local ListItem TempItem;
	local String ResponseStr, SelectedStr;

	if (MapList == None)
		return "<option value=\"\">*** None ***</option>";

	for (TempItem = MapList; TempItem != None; TempItem = TempItem.Next) {
		SelectedStr = "";
		if (TempItem.Data ~= SelectedItem || TempItem.bJustMoved)
			SelectedStr = " selected";
		ResponseStr = ResponseStr$"<option value=\""$FixHTML(TempItem.Data)$"\""$SelectedStr$" title=\""$FixHTML(TempItem.Tag)$"\">"$FixHTML(TempItem.Tag)$"</option>";
	}

	return ResponseStr;
}


function DisplayAccessError(SWARequest Request, SWAResponse Response)
{
  Response.Subst("Title", "<b>Error: </b>");
  Response.Subst("Message", "You do not have sufficient privileges to access this page.");
  IncludeUHTM(Response,MessageUHTM);
}

function DisplayTournamentError(SWARequest Request, SWAResponse Response)
{
  Response.Subst("Title", "<b>Error: </b>");
  Response.Subst("Message", "The server is set to a <b>Tournament</b> mode. You are not allowed to log right now. Wait until the server is public.");
  IncludeUHTM(Response,MessageUHTM);
}

function DisplayOPBanError(SWARequest Request, SWAResponse Response)
{
  Response.Subst("Title", "<b>Error: </b>");
  Response.Subst("Message", "OPBan is not loaded.");
  IncludeUHTM(Response,MessageUHTM);
}

function bool AuthenticateAutomaton(SWARequest Request, SWAResponse Response)
{

	if (opmain==None)
		return False;
	if ((opconf.sAutoName ~= "" || (Caps(Request.UserName) != Caps(opconf.sAutoName)))
		|| (opconf.sAutoPass ~= "" || (Caps(Request.Password) != Caps(opconf.sAutoPass))))
		{
		return False;
		}
	return True;
}

// Player Managment functions

//*****************************************************************************
event Query(SWARequest Request, SWAResponse Response)
{
	local int i;
	local string sURI, temp, Token, User;
	local bool bSession;

	CurRequest = Request;

	// The stylesheet is public, so the login/logout page is styled too.
	if (Request.URI == "/swa2.css")
	{
		Response.SendStandardHeaders("text/css");
		Response.IncludeBinaryFile("swa2.css");
		return;
	}
	if (Request.URI == "/login")
	{
		QueryLogin(Request, Response);
		return;
	}
	if (Request.Username != "" && IsLockedOut(Request.ClientIP))
	{
		Response.FailAuthentication(Config.AdminRealm);
		return;
	}
	// Browsers log in on the login page and send a session cookie; scripts (c00lbot,
	// UpdateScript) keep sending Basic Auth with every request.
	if (Request.Username == "")
	{
		Token = Request.GetCookie("swa2s");
		if (Token != "")
		{
			User = Config.SessionUser(Token, NowMinutes());
			if (User != "")
			{
				Request.Username = User;
				bSession = true;
			}
		}
	}
	if (bSession || Config.CheckUser(Request.Username, Request.Password))
	{
	if (!bSession)
		ClearAuthFailures(Request.ClientIP);
	if ((Request.RequestType == Request_POST || Request.bHasFormData) && Request.IsCrossSite())
	{
		log("SWA: Refused cross-site request from "$Request.ClientIP$" for "$Request.URI$" (user "$Request.Username$").");
		Response.HTTPError(403, "Cross-site requests are not allowed.");
		return;
	}
	sURI=Mid(Request.URI, 1);
	// Log out: Basic Auth has no session, so answer 401 to make the browser forget the
	// login and ask again. "u" is the user who clicked Log out; logging in as another
	// user in the same prompt goes straight in.
	if (sURI == "logout" && bSession)
	{
		Config.EndSession(Token);
		log("SWA: "$Request.UserName$"("$Request.ClientIP$") logged out.");
		SendCookieRedirect(Response, "/login?LoggedOut=1", "swa2s=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0");
		return;
	}
	if (sURI == "logout")
	{
		if (Request.GetVariable("u", "") ~= Request.Username)
		{
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") logged out.");
			Response.FailAuthentication(Config.AdminRealm);
		}
		else
			Response.Redirect("/"$CurrentPlayersPage);
		return;
	}
	// Match query function.  checks URI and calls appropriate input/output function
	if(Config.Privileges(Request.Username)<3 && bTournament)
	{
		DisplayTournamentError(Request, Response);
		return;
	}
	CheckApps();
	sURI=Mid(Request.URI, 1);

	switch (sURI) {
	case "favicon.ico":
		Response.SendStandardHeaders("image/x-icon");
		Response.IncludeBinaryFile("favicon.ico"); break;
	case "":
	case RootPage:
		QueryRoot(Request, Response); break;
	case MenuPage:
		QueryMenu(Request, Response); break;
	case WelcomePage:
		QueryWelcomePage(Request, Response); break;
	case BlankPage:
		QueryBlankPage(Request, Response); break;
	case CurrentPage:
  		QueryCurrent(Request, Response); break;
  	case CurrentMenuPage:
		QueryCurrentMenu(Request, Response); break;
	case CurrentPlayersPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentPlayers(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentGamePage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentGame(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentConsolePage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentConsole(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentConsoleLogPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentConsoleLog(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentConsoleSendPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentConsoleSend(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentMutatorsPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)==2 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentMutators(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentRestartPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)==2 && !bTournament))
			QueryRestartPage(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentRulesPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)==2 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryCurrentRules(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsRestartPage:
		if (Config.Privileges(Request.Username)>3)
			QueryRestartPage(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case CurrentQuickSetPage:
		if (Config.Privileges(Request.Username)>2)
			QueryCurrentQuickSet(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsPage:
		QueryDefaults(Request, Response); break;
	case DefaultsMenuPage:
		QueryDefaultsMenu(Request, Response); break;
	case DefaultsMapsPage:
		if (Config.Privileges(Request.Username)>3)
			QueryDefaultsMaps(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsRulesPage:
		if (Config.Privileges(Request.Username)>3)
			QueryDefaultsRules(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsSettingsPage:
		if (Config.Privileges(Request.Username)>3)
			QueryDefaultsSettings(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsBotsPage:
		if (Config.Privileges(Request.Username)>3)
			QueryDefaultsBots(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsIPPolicyPage:
		if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryDefaultsIPPolicy(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DefaultsChangePasswordPage:
		if (Config.Privileges(Request.Username)>0)
	        	QueryDefaultsChangePassword(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminPage:
		if (Config.Privileges(Request.Username)==5)
	 		QuerySuperAdmin(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminMenuPage:
		if (Config.Privileges(Request.Username)==5)
			QuerySuperAdminMenu(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminServerPage:
		if (Config.Privileges(Request.Username)==5)
			QuerySuperAdminServer(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminWebAdminPage:
		if (Config.Privileges(Request.Username)==5)
	 		QuerySuperAdminWebAdmin(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminRestartPage:
		if (Config.Privileges(Request.Username)==5)
			QueryRestartPage(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case SuperAdminQuickSetConfigPage:
		if (Config.Privileges(Request.Username)==5)
			QuerySuperAdminQuickSetConfig(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case OPBanList:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryBanlist(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case DynaList:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)>2 || (Config.Privileges(Request.Username)<3 && !bTournament) && Config.Privileges(Request.Username)!=0)
			QueryDynalist(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case OPBanOptions:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)==5)
			QueryOptions(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	case EditOPList:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)>2)   // mass edit can wipe a whole list: level 3+
			QueryEditList(Request, Response, True);
		else
			DisplayAccessError(Request, Response);
		break;
	case EditUTlist:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)>2)   // mass edit can wipe a whole list: level 3+
			QueryEditList(Request, Response, False);
		else
			DisplayAccessError(Request, Response);
		break;
	case EditDynaList:
		if (opmain==none)
			DisplayOPBanError(Request, Response);
		else if (Config.Privileges(Request.Username)>2)   // mass edit can wipe a whole list: level 3+
			QueryEditDynalist(Request, Response);
		else
			DisplayAccessError(Request, Response);
		break;
	default:
		if (sURI == "swa2.css")
		{
			Response.SendStandardHeaders("text/css");
			Response.IncludeBinaryFile(sURI);
		}
		else if (sURI == "swa2.js")
		{
			Response.SendStandardHeaders("text/javascript");
			Response.IncludeBinaryFile(sURI);
		}
		else if(Left(sURI, 6) == "flags/" && Right(sURI, 4) == ".png" && InStr(sURI, "..") == -1 && InStr(sURI, "\\") == -1)
		{
			// 469: WebResponse.IncludePath is const, so the flag is read through a sub path.
			Response.SendStandardHeaders("image/png");
			Response.IncludeBinaryFile(sURI);
		}
		else if(Left(sURI, 11) ~= "ServerAdmin") //just in case if anybody would want to use the old link
			Response.Redirect("/");
		else
			Response.SendText("ERROR: Page not found or enabled.");
	}
	}
	else if (AuthenticateAutomaton(Request, Response))
		{
		// Automaton, so do the special automaton stuff
		switch (Mid(Request.URI, 1))
			{
			case "OPlist":
				QueryAutoList(Request, Response, True);		break;
			case "UTlist":
				QueryAutoList(Request, Response, False);		break;
			default:
				Response.SendText("ERROR: Page not found or enabled.");
			}
		}
	else
	{
	  if(Request.Username != "")
	  {
	  	log("SWA: Failed authentification from "$Request.ClientIP$", attempt for "$Request.Username);
	  	RecordAuthFailure(Request.ClientIP);
	  }
	  else if (Request.IsBrowserPage())
	  {
	  	// a browser without (valid) session: the login page, then back to this page
	  	ShowLogin(Response, "", false, Request.URI, "");
	  	return;
	  }
	  else
	  	log("SWA: Connection from "$Request.ClientIP);
	  Response.FailAuthentication(Config.AdminRealm);
	  return;
	}
}

//*****************************************************************************
//*****************************************************************************
//Maybe I'll finish this later ;)
/*function QueryWhoIsPage(SWARequest Request, SWAResponse Response)
{
	if(Spectator.ServerMutate("whois "$
	Response.Subst("WhoIs", Spectator.ServerMutate("whois "$WhoIsNick, true));
	Response.Subst

	IncludeUHTM(Response,WhoIsPage$".uhtm");
	Response.ClearSubst();
}*/

function QueryCurrentPlayers(SWARequest Request, SWAResponse Response)
{
	local string Sort, PlayerListSubst, TempStr;
	local ListItem PlayerList, TempItem;
	local Pawn P, NextP;
	local int PawnCount;
	local string IP, Reason, Time, Pause, TempScore, CountryStuff, KickCells;
	local PlayerPawn PP;
	local TeamGamePlus TG;
	local string GroupRows[6];
	local int GroupCount[6], g, Removed;

	Sort = Request.GetVariable("Sort", "Name");
	if (!(Sort ~= "Name" || Sort ~= "Team" || Sort ~= "Ping" || Sort ~= "Score"))
		Sort = "Name";

	Reason = Request.GetVariable("Reason");
	if (Reason == "")
		Reason = "None";

	// Kick / ban. NextP is taken first: Destroy() takes the pawn out of the list.
	for (P = Level.PawnList; P != None; P = NextP)
	{
		NextP = P.NextPawn;
		if (PlayerPawn(P) == None || P.PlayerReplicationInfo == None || NetConnection(PlayerPawn(P).Player) == None)
			continue;

		if (Request.GetVariable("BanPlayer"$string(P.PlayerReplicationInfo.PlayerID)) != "")
		{
			Removed++;
			BanPlayer(PlayerPawn(P), Request, Reason);
		}
		else if (Request.GetVariable("KickPlayer"$string(P.PlayerReplicationInfo.PlayerID)) != "")
		{
			Removed++;
			P.ClientMessage("________________________________________");
			P.ClientMessage("   - You have been kicked from the server!");
			P.ClientMessage("                                        ");
			P.ClientMessage("   - Reason    : "$Reason);
			P.ClientMessage("   - by Admin  : "$Request.UserName);
			P.ClientMessage("________________________________________");
			Log("SWA: "$Request.UserName$"("$Request.ClientIP$") has kicked player '"$P.PlayerReplicationInfo.PlayerName$"' with reason '"$Reason$"'.");
			P.Destroy();
		}
	}

	for (P = Level.PawnList; P != None; P = P.NextPawn)
	{
		if (!P.bIsPlayer || P.bDeleteMe || SuperServerAdminSpectator(P) != None || P.PlayerReplicationInfo == None)
			continue;
		if (P.PlayerReplicationInfo.PlayerName == "Player")
			continue;

		TempItem = new(None) class'ListItem';
		CountryStuff = "";
		IP = "";
		if (PlayerPawn(P) != None && NetConnection(PlayerPawn(P).Player) != None)
		{
			IP = PlayerPawn(P).GetPlayerNetworkAddress();
			IP = Left(IP, InStr(IP, ":"));
			if (bIpToCountry)
				CountryStuff = CountryFlag(IP);
		}

		PawnCount++;
		TempStr = "";
		if (P.PlayerReplicationInfo.bIsABot)
		{
			// "KickPlayer" must stay in the page for human players: UpdateScript.sh greps for it.
			KickCells = "<td class=\"chk\"></td><td class=\"chk\"></td>";
			TempStr = "&nbsp;(Bot)";
		}
		else
		{
			KickCells = "<td class=\"chk\"><input type=\"checkbox\" name=\"KickPlayer"$P.PlayerReplicationInfo.PlayerID$"\" value=\"kick\" aria-label=\"Kick\"></td><td class=\"chk\"><input type=\"checkbox\" name=\"BanPlayer"$P.PlayerReplicationInfo.PlayerID$"\" value=\"ban\" aria-label=\"Ban IP\"></td>";
			PP = PlayerPawn(P);
			if (bTournament && P.PlayerReplicationInfo.bIsSpectator && P.PlayerReplicationInfo.bWaitingPlayer && PP != None)
			{
				if (PP.bReadyToPlay)
					TempStr = "&nbsp;(Ready)";
				else
					TempStr = "&nbsp;(Waiting ...)";
			}
			else if (P.PlayerReplicationInfo.bIsSpectator)
				TempStr = "&nbsp;(Spectator)";
		}

		TempScore = FormatScore(P.PlayerReplicationInfo);
		// Leading digit = group: 0-3 team, 4 no team, 5 spectators. Stripped on output.
		TempItem.Data = PlayerGroup(P)$"<tr"$TeamClass(P)$"><td>"$CountryStuff$FixHTML(P.PlayerReplicationInfo.PlayerName)$"<span class=\"muted\">"$TempStr$"</span></td><td class=\"team\">"$FixHTML(P.PlayerReplicationInfo.TeamName)$"</td><td class=\"num\">"$P.PlayerReplicationInfo.Ping$"</td><td class=\"num\">"$TempScore$"</td><td>"$IP$"</td>"$KickCells$"</tr>";

		switch (Caps(Sort)) {
			case "NAME":
				TempItem.Tag = P.PlayerReplicationInfo.PlayerName; break;
			case "TEAM":
				TempItem.Tag = PadLeft(P.PlayerReplicationInfo.TeamName, 2, "0"); break;
			case "PING":
				TempItem.Tag = PadLeft(String(P.PlayerReplicationInfo.Ping), 4, "0"); break;
			default:
				TempItem.Tag = PadLeft(String(int(P.PlayerReplicationInfo.Score)), 3, "0"); break;
		}
		if (PlayerList == None)
			PlayerList = TempItem;
		else
			PlayerList.AddSortedElement(PlayerList, TempItem);
	}

	if (PawnCount > 0) {
		// Sorted order first (score descending), then split into groups keeping that order.
		for (TempItem=PlayerList; TempItem!=None; TempItem=TempItem.Next)
		{
			g = int(Left(TempItem.Data, 1));
			GroupCount[g]++;
			if (Sort ~= "Score")
				GroupRows[g] = Mid(TempItem.Data, 1)$GroupRows[g];
			else
				GroupRows[g] = GroupRows[g]$Mid(TempItem.Data, 1);
		}
		TG = TeamGamePlus(Level.Game);
		if (TG == None)  // no teams: one list, spectators last
			PlayerListSubst = GroupRows[4]$GroupRows[5];
		else
			for (g = 0; g < 6; g++)
				if (GroupCount[g] > 0)
					PlayerListSubst = PlayerListSubst$GroupHeader(TG, g, GroupCount[g])$GroupRows[g];
	}
	else  // UpdateScript.sh greps for this text
		PlayerListSubst = "<tr><td colspan=\"7\" class=\"muted\">No Players Connected</td></tr>";

	if (Level.Game.GameReplicationInfo.RemainingTime==0 && Level.Game.GameReplicationInfo.ElapsedTime!=0)
		Time = " - ElapsedTime -"$GetStrTime((Level.Game.GameReplicationInfo.ElapsedTime-22));
	else
		Time = " - TimeLeft "$GetStrTime(Level.Game.GameReplicationInfo.RemainingTime);
	if (Level.Pauser != "")
		Pause = "(Paused)";

	if (bBTScores)
		Response.Subst("Score", "Best cap");
	else
		Response.Subst("Score", "Score");
	if (opconf != None)
		Response.Subst("DynBanHint", "; with \"Dynamic IP ban\" the ban ends after the given days or maps");
	else
		Response.Subst("DynBanHint", "");
	if (opconf != None)
		Response.Subst("IPBanType", "<input type=\"checkbox\" name=\"DynBan\" checked> Dynamic IP Ban for <input type=\"text\" name=\"PeriodValue\" size=\"2\" maxlength=\"2\" value=\"5\"><SELECT NAME=\"PeriodType\"><OPTION value=\"1\" selected>Days</OPTION><OPTION value=\"2\">Maps</OPTION></SELECT>");
	Response.Subst("PlayerList", PlayerListSubst);
	if (bTournament)
		Response.Subst("CurrentGame", FixHTML(Level.Game.GameReplicationInfo.GameName$" in "$Level.Title$"(Tournament)"$Time$Pause));
	else
		Response.Subst("CurrentGame", FixHTML(Level.Game.GameReplicationInfo.GameName$" in "$Level.Title$Time$Pause));
	Response.Subst("PostAction", CurrentPlayersPage);
	Response.Subst("Sort", Sort);
	// After a kick or ban, reload the list (as a plain GET) once the player is gone.
	if (Removed > 0)
		Response.Subst("KickMessage", "<p class=\"loginmsg\" role=\"status\">"$Removed$Eval(Removed == 1, " player", " players")$" removed. The list refreshes in 2 seconds.</p>"
			$"<script>setTimeout(function(){location.replace('/"$CurrentPlayersPage$"?Sort="$Sort$"');},2000);</script>");
	else
		Response.Subst("KickMessage", "");
	// team games: the group headers name the team, so the Team column is hidden (CSS)
	Response.Subst("Grouped", Eval(TeamGamePlus(Level.Game) != None, " grouped", ""));
	IncludeUHTM(Response,CurrentPlayersPage$".uhtm");
}

// Sort order of the players page, limited to the known columns.
function string PlayersSort(SWARequest Request)
{
	local string Sort;

	Sort = Request.GetVariable("Sort", "Name");
	if (Sort ~= "Team" || Sort ~= "Ping" || Sort ~= "Score")
		return Caps(Left(Sort, 1))$Locs(Mid(Sort, 1));
	return "Name";
}

// Group of a row on the players page: the team (0-3) in team games, 4 without a team,
// 5 for spectators.
function int PlayerGroup(Pawn P)
{
	if (P.PlayerReplicationInfo.bIsSpectator)
		return 5;
	if (!Level.Game.bTeamGame || P.PlayerReplicationInfo.Team > 3)
		return 4;
	return P.PlayerReplicationInfo.Team;
}

// Header row above a group on the players page, e.g. "Red - 5 players - score 3".
function string GroupHeader(TeamGamePlus TG, int g, int Count)
{
	local string S, Cls;

	if (g == 5)
		S = "Spectators";
	else if (g == 4)
		S = "No team";
	else
	{
		Cls = " team"$g;
		if (TG.Teams[g] != None)
			S = FixHTML(TG.Teams[g].TeamName);
		else
			S = "Team "$(g + 1);
	}
	if (Count == 1)
		S = S$" &middot; 1 player";
	else
		S = S$" &middot; "$Count$" players";
	if (g < 4 && TG.Teams[g] != None)
		S = S$" &middot; score "$int(TG.Teams[g].Score);
	return "<tr class=\"group"$Cls$"\"><th colspan=\"7\">"$S$"</th></tr>";
}

// Team colour bar for players (not spectators) in team games.
function string TeamClass(Pawn P)
{
	if (!Level.Game.bTeamGame || P.PlayerReplicationInfo.bIsSpectator || P.PlayerReplicationInfo.Team > 3)
		return "";
	return " class=\"team"$P.PlayerReplicationInfo.Team$"\"";
}

// IP ban from the players page: a dynamic OPBan ban (days/maps) when OPBan runs and
// "Dynamic IP Ban" is ticked, otherwise a permanent DENY in the UT IP policies.
function BanPlayer(PlayerPawn P, SWARequest Request, string Reason)
{
	local string IP, comment;
	local int DayTemp, MapTemp, j;

	IP = P.GetPlayerNetworkAddress();
	IP = Left(IP, InStr(IP, ":"));

	P.ClientMessage("________________________________________");
	P.ClientMessage("   - Your IP has been banned from the server!");
	P.ClientMessage("                                        ");
	P.ClientMessage("   - Reason    : "$Reason);

	if (Request.GetVariable("DynBan") != "" && opconf != None)
	{
		if (Request.GetVariable("PeriodType") == "1")
		{
			DayTemp = Clamp(int(Request.GetVariable("PeriodValue")), 1, 99);
			P.ClientMessage("   - Period    : "$DayTemp$" Days");
		}
		else
		{
			MapTemp = Clamp(int(Request.GetVariable("PeriodValue")), 1, 99);
			P.ClientMessage("   - Period    : "$MapTemp$" Maps");
		}
		comment = SanitizeBanText(Request.GetVariable("Reason"))$":"$SanitizeBanText(P.PlayerReplicationInfo.PlayerName);
		opconf.AddDynaBan(IP, DayTemp, MapTemp, comment);
		Log("SWA: "$Request.UserName$"("$Request.ClientIP$") has added a dynamic IP ban ("$DayTemp$" days, "$MapTemp$" maps) for player '"$P.PlayerReplicationInfo.PlayerName$"', IP: "$IP$", with reason '"$Reason$"'.");
	}
	else if (Level.Game.CheckIPPolicy(P.GetPlayerNetworkAddress()))
	{
		for (j = 0; j < ArrayCount(Level.Game.IPPolicies); j++)
			if (Level.Game.IPPolicies[j] == "")
				break;
		if (j < ArrayCount(Level.Game.IPPolicies))
		{
			Level.Game.IPPolicies[j] = "DENY,"$IP;
			Level.Game.SaveConfig();
		}
		else
			Log("SWA: The UT IP ban list (IPPolicies) is full, the ban is not saved.");
		Log("SWA: "$Request.UserName$"("$Request.ClientIP$") has added IP Ban for player '"$P.PlayerReplicationInfo.PlayerName$"', IP: "$IP$", with reason '"$Reason$"'.");
	}

	P.ClientMessage("   - by Admin  : "$Request.UserName);
	P.ClientMessage("   - Your IP   : "$IP);
	P.ClientMessage("________________________________________");
	P.Destroy();
}

// Score column; on BunnyTrack maps the score encodes the best cap time.
function string FormatScore(PlayerReplicationInfo PRI)
{
	local int intScore, secs;
	local string sec;

	if (!bBTScores)
		return string(int(PRI.Score));
	if (PRI.Score == 0 || PRI.bIsABot)
		return "0:00";
	intScore = int(2000 - PRI.Score);
	if (intScore <= 1 || intScore >= 1999)
		return "0:00";
	secs = intScore % 60;
	if (secs < 10)
		sec = "0"$string(secs);
	else
		sec = string(secs);
	return string(intScore / 60)$":"$sec;
}

// Country flag from IpToCountry ("!..." means not resolved yet).
function string CountryFlag(string IP)
{
	local string temp, prefix2, country;

	temp = IpToCountry.GetItemName(IP);
	if (Left(temp, 1) == "!")
		return "";
	prefix2 = Config.SelElem(temp, 5); // short prefix
	country = Config.SelElem(temp, 3);
	if (Len(prefix2) != 2 || !IsSafeClassName("a."$prefix2))
		return "";
	return "<img src=\"flags/"$prefix2$".png\" class=\"flag\" title=\""$FixHTML(country)$"\"/>";
}

function QueryCurrentGame(SWARequest Request, SWAResponse Response)
{
	local ListItem ExcludeMaps, IncludeMaps;
	local class<DeathMatchPlus> NewClass;
	local string NewGameType, Map;

	if (Request.GetVariable("SwitchGameTypeAndMap", "") != "" || Request.GetVariable("SwitchGameType", "") != "")
	{
		// The game type controls are only shown to these users; enforce it for the POST too.
		if (!CanSwitchGameType(Request))
		{
			DisplayAccessError(Request, Response);
			return;
		}
		NewGameType = ValidateGameType(Request.GetVariable("GameTypeSelect"));
		if (NewGameType != "")
			NewClass = class<DeathMatchPlus>(DynamicLoadObject(NewGameType, class'Class', true));
		if (NewClass == None)
		{
			DisplayMessage(Response, "Error", "Unknown game type.");
			return;
		}
	}

	if (Request.GetVariable("SwitchGameTypeAndMap", "") != "") {
		Map = ValidateMap(Request.GetVariable("MapSelect"), NewGameType);
		if (Map == "")
		{
			DisplayMessage(Response, "Error", "Unknown map.");
			return;
		}
		Level.ServerTravel(BuildTravelURL(Map, NewGameType, UsedMutators()), false);
		Response.Subst("Title", "Please Wait");
		Response.Subst("Message", "The server is now switching to map '"$FixHTML(Map)$"' and game type '"$FixHTML(NewClass.default.GameName)$"'.  Please allow 10-15 seconds while the server changes levels.");
		log("SWA: "$Request.UserName$"("$Request.ClientIP$") has switched map to '"$Map$"' and game type to '"$NewGameType$"'.");
		IncludeUHTM(Response,MessageUHTM);
	}
	else if (Request.GetVariable("SwitchGameType", "") != "") {

		ReloadExcludeMaps(ExcludeMaps, NewGameType);
//Disabled in order to load all maps.
//		ReloadIncludeMaps(ExcludeMaps, IncludeMaps, NewGameType);

		Response.Subst("GameTypeButton", "");
		Response.Subst("MapButton", "<input type=\"submit\" name=\"SwitchGameTypeAndMap\" value=\"Switch\">");
		Response.Subst("GameTypeSelect", "<td>Game type</td><td>"$FixHTML(NewClass.default.GameName)$"<input type=\"hidden\" name=\"GameTypeSelect\" value=\""$FixHTML(NewGameType)$"\"></td>");
		Response.Subst("MapSelect", GenerateMapListSelect(ExcludeMaps));
		Response.Subst("PostAction", CurrentGamePage);
		IncludeUHTM(Response,CurrentGamePage$".uhtm");
	}
	else if (Request.GetVariable("SwitchMap", "") != "") {
		Map = ValidateMap(Request.GetVariable("MapSelect"), string(Level.Game.Class));
		if (Map == "")
		{
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") tried to switch to an unknown map.");
			DisplayMessage(Response, "Error", "Unknown map.");
			return;
		}
		Level.ServerTravel(BuildTravelURL(Map, string(Level.Game.Class), UsedMutators()), false);
		Response.Subst("Title", "Please Wait");
		Response.Subst("Message", "The server is now switching to map '"$FixHTML(Map)$"'.    Please allow 10-15 seconds while the server changes levels.");
		log("SWA: "$Request.UserName$"("$Request.ClientIP$") has switched map to '"$Map$"'.");
		IncludeUHTM(Response,MessageUHTM);

	}
	else {
		ReloadExcludeMaps(ExcludeMaps, String(Level.Game.Class));
//Disabled in order to load all maps.
//		ReloadIncludeMaps(ExcludeMaps, IncludeMaps, String(Level.Game.Class));

		Response.Subst("MapButton", "<input type=\"submit\" name=\"SwitchMap\" value=\"Switch\">");
		if (Config.Privileges(Request.Username)>3 || (Config.Privileges(Request.Username)==2 && !bTournament) && Config.Privileges(Request.Username)!=0)
		{
			Response.Subst("GameTypeSelect", "<td>Game type</td><td><select name=\"GameTypeSelect\">"$GenerateGameTypeOptions(String(Level.Game.Class))$"</select></td>");
			Response.Subst("GameTypeButton", "<td><input type=\"submit\" name=\"SwitchGameType\" value=\"Switch\"></td>");
		}
		Response.Subst("MapSelect", GenerateMapListSelect(ExcludeMaps, Left(string(Level), InStr(string(Level), "."))$".unr") );		Response.Subst("PostAction", CurrentGamePage);
		IncludeUHTM(Response,CurrentGamePage$".uhtm");
	}
}

function QueryCurrentConsole(SWARequest Request, SWAResponse Response)
{
	local String SendStr, OutStr, Error, Keep;

	// Plain text is a chat message to everyone; text starting with / is a console command.
	SendStr = Request.GetVariable("SendText", "");
	if (Left(SendStr, 1) != "/")
	{
		if (SendStr != "")
		{
			Spectator2.BroadcastMessage(Request.UserName$"(Web): "$SendStr);
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") has sent a message to server's console('"$SendStr$"').");
			Spectator2.LastMessageWindow = Level.TimeSeconds - 20;
		}
	}
	else
	{
		SendStr = Mid(SendStr, 1);
		if (Left(SendStr, 7) ~= "mutate ")
		{
			if (Config.Privileges(Request.Username) > 3)
			{
				Spectator.ServerMutate(Mid(SendStr, 7));
				log("SWA: "$Request.UserName$"("$Request.ClientIP$") has used a mutate command('"$Mid(SendStr, 7)$"').");
			}
			else
				Error = "/mutate needs level 4 (Server admin) or higher.";
		}
		else if (SendStr == "")
			Error = "Type a command after the /.";
		else if (Config.Privileges(Request.Username) == 5)
		{
			OutStr = Level.ConsoleCommand(SendStr);
			if (OutStr != "")
				Spectator.AddMessage(None, OutStr, 'Console');
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") has used a command('"$SendStr$"').");
		}
		else
			Error = "Console commands other than /mutate need level 5 (Super admin).";
		if (Error != "")
			Keep = "/"$SendStr;
	}

	if (Error == "")
		Response.Subst("ConsoleMessage", "");
	else
		Response.Subst("ConsoleMessage", "<p class=\"loginmsg error\" role=\"alert\">"$FixHTML(Error)$"</p>");
	Response.Subst("SendText", FixHTML(Keep));
	Response.Subst("LogURI", CurrentConsoleLogPage);
	Response.Subst("SayURI", CurrentConsoleSendPage);
	IncludeUHTM(Response,CurrentConsolePage$".uhtm");
}

function QueryCurrentConsoleLog(SWARequest Request, SWAResponse Response)
{
	local ListItem TempItem;
	local String LogSubst, LogStr;
	local int i;

	for (TempItem = Spectator.MessageList; TempItem != None; TempItem = TempItem.Next)
	{
		if(TempItem.Data!="")
			LogSubst = LogSubst$"&gt; "$FixHTML(TempItem.Data)$"<br>";
	}

	Response.Subst("LogText", LogSubst);
	IncludeUHTM(Response,CurrentConsoleLogPage$".uhtm");
}

function QueryRestartPage(SWARequest Request, SWAResponse Response)
{
	if (Request.RequestType != Request_POST || Request.GetVariable("Restart", "") == "")
	{
		Response.Subst("PostAction", "/"$CurrentPageName());
		IncludeUHTM(Response, "restart.uhtm");
		return;
	}
	Level.ServerTravel(BuildTravelURL(Left(string(Level), InStr(string(Level), "."))$".unr", string(Level.Game.Class), UsedMutators()), false);
	Response.Subst("Title", "Please Wait");
	Response.Subst("Message", "The server is now restarting the current map.  Please allow 10-15 seconds while the server changes levels.");
	log("SWA: "$Request.UserName$"("$Request.ClientIP$") has restarted the current map !");
	IncludeUHTM(Response,MessageUHTM);
}

function QueryCurrentMutators(SWARequest Request, SWAResponse Response)
{
	local ListItem TempItem;
	local int Count, i;
	local string Mut;

	if (Request.GetVariable("AddMutator", "") != "")
	{
		Count = Request.GetVariableCount("ExcludeMutatorsSelect");
		for (i = 0; i < Count; i++)
		{
			Mut = Request.GetVariableNumber("ExcludeMutatorsSelect", i);
			TempItem = FindAvailMutator(Mut);
			if (TempItem != None && !ListContains(ActiveMutators, TempItem.Data))
			{
				ActiveMutators = ListAppend(ActiveMutators, TempItem.Data);
				JustMovedMutators = ListAppend(JustMovedMutators, TempItem.Data);
			}
		}
	}
	else if (Request.GetVariable("DelMutator", "") != "")
	{
		Count = Request.GetVariableCount("IncludeMutatorsSelect");
		for (i = 0; i < Count; i++)
		{
			Mut = Request.GetVariableNumber("IncludeMutatorsSelect", i);
			if (ListContains(ActiveMutators, Mut))
			{
				ActiveMutators = ListRemove(ActiveMutators, Mut);
				JustMovedMutators = ListAppend(JustMovedMutators, Mut);
			}
		}
	}
	else if (Request.GetVariable("AddAllMutators", "") != "")
	{
		for (TempItem = AvailMutators; TempItem != None; TempItem = TempItem.Next)
			if (!ListContains(ActiveMutators, TempItem.Data))
			{
				ActiveMutators = ListAppend(ActiveMutators, TempItem.Data);
				JustMovedMutators = ListAppend(JustMovedMutators, TempItem.Data);
			}
	}
	else if (Request.GetVariable("DelAllMutators", "") != "")
	{
		// Removes the listed mutators; the "Other Mutators" stay.
		for (TempItem = AvailMutators; TempItem != None; TempItem = TempItem.Next)
			if (ListContains(ActiveMutators, TempItem.Data))
			{
				ActiveMutators = ListRemove(ActiveMutators, TempItem.Data);
				JustMovedMutators = ListAppend(JustMovedMutators, TempItem.Data);
			}
	}
	else if (Request.GetVariable("UpdateOther", "") != "")
		UpdateURLMutators(Request.GetVariable("OtherMutators"));
	else if (Request.GetVariable("SetMutators", "") != "")
		SetMutatorsFromForm(Request);

	RebuildMutatorLists();
	if (Request.RequestType == Request_POST)
		log("SWA: "$Request.UserName$"("$Request.ClientIP$") set the mutators for the next map to '"$ActiveMutators$"'.");

	Response.Subst("ExcludeMutatorsOptions", GenerateMutatorListSelect(ExcludeMutators));
	Response.Subst("IncludeMutatorsOptions", GenerateMutatorListSelect(IncludeMutators));
	Response.Subst("OtherMutators", FixHTML(URLMutators));
	Response.Subst("AvailOptions", GenerateMutatorOptions(false));
	Response.Subst("UsedOptions", GenerateMutatorOptions(true));
	Response.Subst("ActiveOrder", GenerateActiveOrder());
	Response.Subst("MutatorCount", string(CountAvailMutators()));
	Response.Subst("PostAction", CurrentMutatorsPage);
	IncludeUHTM(Response,CurrentMutatorsPage$".uhtm");
}

function QueryCurrentRules(SWARequest Request, SWAResponse Response)
{
	local String GamePassword, MaxPlayers, MaxSpectators, MuteSpectators;

	MaxPlayers = Level.ConsoleCommand("get engine.gameinfo MaxPlayers");
	MaxSpectators = Level.ConsoleCommand("get engine.gameinfo MaxSpectators");
	GamePassword = Level.ConsoleCommand("get engine.gameinfo GamePassword");
	MuteSpectators =Level.ConsoleCommand("get engine.gameinfo bMuteSpectators");

	if (Request.GetVariable("Apply", "") != "")
	{
		GamePassword = Request.GetVariable("GamePassword", "");
		if (!IsValidGamePassword(GamePassword))
		{
			// 400 so that c00lbot (which only checks the status) retries instead of
			// believing the password was set.
			Response.HTTPResponse("HTTP/1.1 400 Bad Request");
			DisplayMessage(Response, "Error", "The game password may not contain spaces, quotes or control characters.");
			return;
		}
		MaxPlayers = string(Clamp(int(Request.GetVariable("MaxPlayers", MaxPlayers)), 0, 64));
		MaxSpectators = string(Clamp(int(Request.GetVariable("MaxSpectators", MaxSpectators)), 0, 64));
		if (Request.GetVariable("MuteSpectators", "") != "" && !(Request.GetVariable("MuteSpectators") ~= "false"))
			MuteSpectators = "True";
		else
			MuteSpectators = "False";
		Level.ConsoleCommand("set engine.gameinfo MaxPlayers "$MaxPlayers);
		Level.ConsoleCommand("set engine.gameinfo MaxSpectators "$MaxSpectators);
		Level.ConsoleCommand("set engine.gameinfo GamePassword "$GamePassword);
		Level.ConsoleCommand("set engine.gameinfo bMuteSpectators "$MuteSpectators);
		if (GamePassword == "")
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") has changed CurrentRules to MaxPlayers="$MaxPlayers$", MaxSpectators="$MaxSpectators$", no game password, MuteSpectators="$MuteSpectators);
		else
			log("SWA: "$Request.UserName$"("$Request.ClientIP$") has changed CurrentRules to MaxPlayers="$MaxPlayers$", MaxSpectators="$MaxSpectators$", game password set, MuteSpectators="$MuteSpectators);
	}
	Response.Subst("GamePassword", FixHTML(GamePassword));
	Response.Subst("MaxPlayers", FixHTML(MaxPlayers));
	Response.Subst("MaxSpectators", FixHTML(MaxSpectators));
	if(MuteSpectators~="true")
	Response.Subst("MuteSpectators", " checked");
	else
	Response.Subst("MuteSpectators", "");

	Response.Subst("PostAction", CurrentRulesPage);
	IncludeUHTM(Response,CurrentRulesPage$".uhtm");
}

function QueryCurrentQuickSet(SWARequest Request, SWAResponse Response)
{
	local ListItem ExcludeMaps, IncludeMaps;
	local string NewGameType, GameType, GamePassword;
	local int ArrayNum;
	local class<GameInfo> GameClass;
	local String Map;

	// Every step posts the QuickSet slot in GameTypeSelect: check it once, up front.
	if (Request.GetVariable("GameTypeSelect", "") != "")
	{
		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		if (ArrayNum < 0 || ArrayNum >= ArrayCount(Config.QuickSetConf) || Config.QuickSetConf[ArrayNum] == ""
			|| ValidateGameType(Config.SelElem(Config.QuickSetConf[ArrayNum], 3)) == "")
		{
			DisplayMessage(Response, "Error", "Unknown QuickSet option.");
			return;
		}
	}

	if (Request.GetVariable("SwitchGameTypeAndMap", "") != "")
	{
		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		// Validate before the game defaults are changed and saved below.
		if (ValidateMap(Request.GetVariable("MapSelect"), Config.SelElem(Config.QuickSetConf[ArrayNum], 3)) == "")
		{
			DisplayMessage(Response, "Error", "Unknown map.");
			return;
		}
		if (!IsValidGamePassword(Request.GetVariable("GamePassword")))
		{
			DisplayMessage(Response, "Error", "The game password may not contain spaces, quotes or control characters.");
			return;
		}
		GameType = Config.SelElem(Config.QuickSetConf[ArrayNum], 3);
		GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));
		if(Config.SelElem(Config.QuickSetConf[ArrayNum], 4)~="true")
			Level.ConsoleCommand("set "$Config.SelElem(Config.QuickSetConf[ArrayNum], 3)$" bTournament True");
		else if(Config.SelElem(Config.QuickSetConf[ArrayNum], 4)~="false" || Config.SelElem(Config.QuickSetConf[ArrayNum], 4)~="")
			Level.ConsoleCommand("set "$Config.SelElem(Config.QuickSetConf[ArrayNum], 3)$" bTournament False");
		Level.ConsoleCommand("set engine.gameinfo GamePassword "$Request.GetVariable("GamePassword"));

		class<DeathMatchPlus>(GameClass).Default.MaxPlayers = int(String(min(max(int(Request.GetVariable("PlayersSelect")), 0),32)));

		class<DeathMatchPlus>(GameClass).Default.MaxSpectators = int(String(max(int(Request.GetVariable("SpecSelect")), 0)));

		class<DeathMatchPlus>(GameClass).Default.bMultiWeaponStay = bool(Config.SelElem(Config.QuickSetConf[ArrayNum], 9));

		class<DeathMatchPlus>(GameClass).Default.bTournament = bool(Config.SelElem(Config.QuickSetConf[ArrayNum], 4));

		if (class<DeathMatchPlus>(GameClass) != None && class<Assault>(GameClass) == None)
    		if (class<TeamGamePlus>(GameClass) != None)
    			class<TeamGamePlus>(GameClass).Default.GoalTeamScore = float(String(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 5)), 0)));
	    	else
    			class<DeathMatchPlus>(GameClass).Default.FragLimit = float(String(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 5)), 0)));

		if(class<LastManStanding>(GameClass) == None){
			class<DeathMatchPlus>(GameClass).Default.TimeLimit = float(String(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 6)), 0)));
			class<DeathMatchPlus>(GameClass).Default.bForceRespawn = bool(Config.SelElem(Config.QuickSetConf[ArrayNum], 8));
			}

		if(class<TeamGamePlus>(GameClass) != None && !ClassIsChildOf( GameClass, class'CTFGame' ) && !ClassIsChildOf( GameClass, class'Assault' ) )
			class<TeamGamePlus>(GameClass).Default.MaxTeams = Min(Max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 11)), 2), 4);

		if (class<TeamGamePlus>(GameClass) != None){
   			class<TeamGamePlus>(GameClass).Default.FriendlyFireScale = float(String(min(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 10)), 0), 100)))/100.0;
			class<TeamGamePlus>(GameClass).Default.bPlayersBalanceTeams = bool(Config.SelElem(Config.QuickSetConf[ArrayNum], 7));}

		switch (Config.SelElem(Config.QuickSetConf[ArrayNum], 12)) {
		case "0":
			class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = false;
			class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = false;
			break;
		case "1":
			class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = false;
			class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = true;
			break;
		case "2":
			class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = true;
			class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = true;
			break;
			}

		class<DeathMatchPlus>(GameClass).Default.GameSpeed = min(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 13)), 10), 200) / 100.0;

		class<DeathMatchPlus>(GameClass).Default.AirControl = min(max(int(Config.SelElem(Config.QuickSetConf[ArrayNum], 14)), 0), 100) / 100.0;

		class<DeathMatchPlus>(GameClass).Default.bUseTranslocator = bool(Config.SelElem(Config.QuickSetConf[ArrayNum], 15));


		GameClass.Static.StaticSaveConfig();

		if(ArrayNum==0 || Config.SelElem(Config.QuickSetConf[ArrayNum], 18)~="True")
		{
			Level.ConsoleCommand("set engine.gameinfo MaxPlayers "$Config.SelElem(Config.QuickSetConf[ArrayNum], 16));
			Level.ConsoleCommand("set engine.gameinfo MaxSpectators "$Config.SelElem(Config.QuickSetConf[ArrayNum], 17));
		}
		if(ArrayNum==0)
			Level.ConsoleCommand("set engine.gameinfo GamePassword");
		Map=ValidateMap(Request.GetVariable("MapSelect"), GameType);
		if (Map == "")
		{
			DisplayMessage(Response, "Error", "Unknown map.");
			return;
		}
		Level.ServerTravel(BuildTravelURL(Map, GameType, Config.SelElem(Config.QuickSetConf[ArrayNum], 2)), false);
		Response.Subst("Title", "Please Wait");
		Response.Subst("Message", "The server is now switching to map '"$FixHTML(Map)$"' and custom set game type to '"$FixHTML(Config.SelElem(Config.QuickSetConf[ArrayNum], 1))$"'.  Please allow 10-15 seconds while the server changes levels.");
		log("SWA: "$Request.UserName$"("$Request.ClientIP$") has switched to a QuickSet Mode '"$Config.SelElem(Config.QuickSetConf[ArrayNum], 1)$"'.");
		IncludeUHTM(Response,MessageUHTM);
	}
	else if (Request.GetVariable("SwitchGameType", "") != "" ) {

		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		ReloadExcludeMaps(ExcludeMaps, Config.SelElem(Config.QuickSetConf[ArrayNum], 3));

		if(GenerateMapListSelect(ExcludeMaps)!="<option value=\"\">*** None ***</option>")
		{
			Response.Subst("GameTypeButton", "");
			if(ArrayNum == 0)
				Response.Subst("RestartButton", "<input type=\"submit\" name=\"SwitchGameTypeAndMap\" value=\"Set and Restart\">");
			else if(Config.SelElem(Config.QuickSetConf[ArrayNum], 18)~="true")
				//that's not really a map select button but that was easier this way :)
				//go directly to the password part
				Response.Subst("MapButton", "<input type=\"submit\" name=\"Password\" value=\"Next\">");
			else
				Response.Subst("MapButton", "<input type=\"submit\" name=\"Players\" value=\"Next\">");
			Response.Subst("GameTypeSelect", FixHTML(Config.SelElem(Config.QuickSetConf[ArrayNum], 1))$"<input type=\"hidden\" name=\"GameTypeSelect\" value=\""$ArrayNum$"\">");
			Response.Subst("MapSelect", "<td nowrap width=\"50\">Map:</td><td><select name=\"MapSelect\">"$GenerateMapListSelect(ExcludeMaps)$"</select></td>");
			Response.Subst("PostAction", CurrentQuickSetPage);
			IncludeUHTM(Response,CurrentQuickSetPage$".uhtm");
		}
		else
		{
			Response.Subst("Title", "Error");
			Response.Subst("Message", "GameType not properly set or there are no maps.");
			IncludeUHTM(Response,MessageUHTM);
		}
	}
	else if (Request.GetVariable("Players", "") != "") {
		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		Response.Subst("GameTypeButton", "");
		Response.Subst("MapButton", "");
		Response.Subst("GameTypeSelect", FixHTML(Config.SelElem(Config.QuickSetConf[ArrayNum], 1))$"<input type=\"hidden\" name=\"GameTypeSelect\" value=\""$ArrayNum$"\">");
		Response.Subst("MapSelect", "<td nowrap width=\"50\">Map:</td><td nowrap>"$FixHTML(Left(Request.GetVariable("MapSelect"), Len(Request.GetVariable("MapSelect")) - 4))$"<input type=\"hidden\" name=\"MapSelect\" value=\""$FixHTML(Request.GetVariable("MapSelect"))$"\"></td>");
		Response.Subst("PlayersButton", "<input type=\"submit\" name=\"Password\" value=\"Next\">");
		Response.Subst("PlayersSelect", "<td nowrap>Players/Spec:</td><td><input type=\"text\" name=\"PlayersSelect\" maxlength=\"2\" size=\"3\" value=\""$Level.ConsoleCommand("get engine.gameinfo MaxPlayers")$"\">");
		Response.Subst("SpecSelect", "<select name=\"SpecSelect\"><option value=\"0\">No Spec</option><option value=\"1\">1</option><option value=\"2\">2</option><option value=\"3\">3</option><option value=\"4\">4</option></select></td>");
		Response.Subst("PostAction", CurrentQuickSetPage);
		IncludeUHTM(Response,CurrentQuickSetPage$".uhtm");
	}
	else if (Request.GetVariable("Password", "") != "") {
		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		GamePassword = Level.ConsoleCommand("get engine.gameinfo GamePassword");
		Response.Subst("GameTypeButton", "");
		Response.Subst("MapButton", "");
		Response.Subst("GameTypeSelect", FixHTML(Config.SelElem(Config.QuickSetConf[ArrayNum], 1))$"<input type=\"hidden\" name=\"GameTypeSelect\" value=\""$ArrayNum$"\">");
		Response.Subst("MapSelect", "<td nowrap width=\"50\">Map:</td><td nowrap>"$FixHTML(Left(Request.GetVariable("MapSelect"), Len(Request.GetVariable("MapSelect")) - 4))$"<input type=\"hidden\" name=\"MapSelect\" value=\""$FixHTML(Request.GetVariable("MapSelect"))$"\"></td>");
//		Response.Subst("MapSelect", "<td nowrap>Switch Map:</td><td><select name=\"MapSelect\">"$Request.GetVariable("MapSelect")$"<input type=\"hidden\" name=\"MapSelect\" value=\""$FixHTML(Request.GetVariable("MapSelect"))$"\"></select></td>");
		Response.Subst("PlayersButton", "");
		//quick way to test if we were in the player set part
		if(Request.GetVariable("SpecSelect") != "")
		{
			Response.Subst("PlayersSelect", "<td nowrap width=\"50\">Players/Spec:</td><td>"$String(min(max(int(Request.GetVariable("PlayersSelect")), 0),32))$"<input type=\"hidden\" name=\"PlayersSelect\" value=\""$String(min(max(int(Request.GetVariable("PlayersSelect")), 0),32))$"\">");
			Response.Subst("SpecSelect", " - "$FixHTML(Request.GetVariable("SpecSelect"))$"<input type=\"hidden\" name=\"SpecSelect\" value=\""$FixHTML(Request.GetVariable("SpecSelect"))$"\"></td></td>");
		}
		Response.Subst("Password", "<td nowrap width=\"50\">Password</td><td><input type=\"text\" name=\"GamePassword\" size=\"25\" value=\""$FixHTML(GamePassword)$"\"></td>");
		Response.Subst("PasswordButton", "<input type=\"submit\" name=\"Ready\" value=\"Next\">");
		Response.Subst("PostAction", CurrentQuickSetPage);
		IncludeUHTM(Response,CurrentQuickSetPage$".uhtm");
	}
	else if (Request.GetVariable("Ready", "") != "" ) {
		ArrayNum = int(Request.GetVariable("GameTypeSelect"));
		Response.Subst("GameTypeButton", "");
		Response.Subst("MapButton", "");
		Response.Subst("GameTypeSelect", FixHTML(Config.SelElem(Config.QuickSetConf[ArrayNum], 1))$"<input type=\"hidden\" name=\"GameTypeSelect\" value=\""$ArrayNum$"\">");
		Response.Subst("MapSelect", "<td nowrap width=\"50\">Map:</td><td nowrap>"$FixHTML(Left(Request.GetVariable("MapSelect"), Len(Request.GetVariable("MapSelect")) - 4))$"<input type=\"hidden\" name=\"MapSelect\" value=\""$FixHTML(Request.GetVariable("MapSelect"))$"\"></td>");
		Response.Subst("PlayersButton", "");
		if(Request.GetVariable("SpecSelect") != "")
		{
			Response.Subst("PlayersSelect", "<td nowrap width=\"50\">Players/Spec:</td><td>"$String(min(max(int(Request.GetVariable("PlayersSelect")), 0),32))$"<input type=\"hidden\" name=\"PlayersSelect\" value=\""$String(min(max(int(Request.GetVariable("PlayersSelect")), 0),32))$"\">");
			Response.Subst("SpecSelect", " - "$FixHTML(Request.GetVariable("SpecSelect"))$"<input type=\"hidden\" name=\"SpecSelect\" value=\""$FixHTML(Request.GetVariable("SpecSelect"))$"\"></td></td>");
		}
		Response.Subst("Password", "<td nowrap width=\"50\">Password:</td><td>"$FixHTML(Request.GetVariable("GamePassword"))$"<input type=\"hidden\" name=\"GamePassword\" value=\""$FixHTML(Request.GetVariable("GamePassword"))$"\"></td>");
		Response.Subst("PasswordButton", "");
		Response.Subst("RestartButton", "<input type=\"submit\" name=\"SwitchGameTypeAndMap\" value=\"Set and Restart\">");
		Response.Subst("PostAction", CurrentQuickSetPage);
		IncludeUHTM(Response,CurrentQuickSetPage$".uhtm");
	}
	else if(GenerateQuickSetOptions()!=""){
//Disabled in order to load all maps.
//		ReloadIncludeMaps(ExcludeMaps, IncludeMaps, String(Level.Game.Class));

		Response.Subst("GameTypeButton", "<input type=\"submit\" name=\"SwitchGameType\" value=\"Switch\">");
		Response.Subst("MapButton", "");
		Response.Subst("GameTypeSelect", "<select name=\"GameTypeSelect\">"$GenerateQuickSetOptions()$"</select>");
		Response.Subst("MapSelect", "");
		Response.Subst("PostAction", CurrentQuickSetPage);
		IncludeUHTM(Response,CurrentQuickSetPage$".uhtm");
	}
	else
		Response.SendText("ERROR: No QuickSet Options are set !.");
}

//*****************************************************************************
function QueryDefaultsMaps(SWARequest Request, SWAResponse Response)
{
	local String GameType, MapListType;
	local ListItem ExcludeMaps, IncludeMaps, TempItem;
	local int i, Count, MoveCount;

	// load saved entries from the page
	GameType = RequestGameType(Request);
	MapListType = Request.GetVariable("MapListType", "Custom");

	ReloadExcludeMaps(ExcludeMaps, GameType);
	ReloadIncludeMaps(ExcludeMaps, IncludeMaps, GameType);


	if (Request.GetVariable("MapListSet", "") != "") {
		MapListType = Request.GetVariable("MapListSelect", "Custom");
		if (MapListType != "Custom")
		{
			ApplyMapList(ExcludeMaps, IncludeMaps, GameType, MapListType);

			UpdateDefaultMaps(GameType, IncludeMaps);
		}
	}
	else if (Request.GetVariable("AddMap", "") != "") {
		Count = Request.GetVariableCount("ExcludeMapsSelect");
		for (i=0; i<Count; i++)
		{
			if (ExcludeMaps != None)
			{
				TempItem = ExcludeMaps.DeleteElement(ExcludeMaps, Request.GetVariableNumber("ExcludeMapsSelect", i));
				if (TempItem != None)
				{
					TempItem.bJustMoved = true;
					if (IncludeMaps == None)
						IncludeMaps = TempItem;
					else
						IncludeMaps.AddElement(TempItem);
				}
				else
					Log("SWA: Exclude map not found: "$Request.GetVariableNumber("ExcludeMapsSelect", i));
			}
		}
		MapListType = "Custom";
		UpdateDefaultMaps(GameType, IncludeMaps);
	}
	else if (Request.GetVariable("DelMap", "") != "" && Request.GetVariableCount("IncludeMapsSelect") > 0) {
		Count = Request.GetVariableCount("IncludeMapsSelect");
		for (i=0; i<Count; i++)
		{
			if (IncludeMaps != None)
			{
				TempItem = IncludeMaps.DeleteElement(IncludeMaps, Request.GetVariableNumber("IncludeMapsSelect", i));
				if (TempItem != None)
				{
					TempItem.bJustMoved = true;
					if (ExcludeMaps == None)
						ExcludeMaps = TempItem;
					else
						ExcludeMaps.AddSortedElement(ExcludeMaps, TempItem);
				}
				else
					Log("SWA: Include map not found: "$Request.GetVariableNumber("IncludeMapsSelect", i));
			}
		}
		MapListType = "Custom";
		UpdateDefaultMaps(GameType, IncludeMaps);
	}
	else if (Request.GetVariable("AddAllMap", "") != "") {
		while (ExcludeMaps != None)
		{
			TempItem = ExcludeMaps.DeleteElement(ExcludeMaps);
			if (TempItem != None)
			{
				TempItem.bJustMoved = true;
				if (IncludeMaps == None)
					IncludeMaps = TempItem;
				else
					IncludeMaps.AddElement(TempItem);
			}
		}
		MapListType = "Custom";
		UpdateDefaultMaps(GameType, IncludeMaps);
	}
	else if (Request.GetVariable("DelAllMap", "") != "") {
		while (IncludeMaps != None)
		{
			TempItem = IncludeMaps.DeleteElement(IncludeMaps);
			if (TempItem != None)
			{
				TempItem.bJustMoved = true;
				if (ExcludeMaps == None)
					ExcludeMaps = TempItem;
				else
					ExcludeMaps.AddSortedElement(ExcludeMaps, TempItem);
			}
		}
		MapListType = "Custom";
		UpdateDefaultMaps(GameType, IncludeMaps);	// IncludeMaps should be None now.
	}
	else if (Request.GetVariable("MoveMap", "") != "") {
		MoveCount = int(Abs(float(Request.GetVariable("MoveMapCount"))));
		if (MoveCount != 0) {
			Count = Request.GetVariableCount("IncludeMapsSelect");
			if (Request.GetVariable("MoveMap") ~= "Down") {
				for (TempItem = IncludeMaps; TempItem.Next != None; TempItem = TempItem.Next);
				for (TempItem = TempItem; TempItem != None; TempItem = TempItem.Prev) {
					for (i=0; i<Count; i++) {
						if (TempItem.Data ~= Request.GetVariableNumber("IncludeMapsSelect", i)) {
							TempItem.bJustMoved = true;
							IncludeMaps.MoveElementDown(IncludeMaps, TempItem, MoveCount);
							break;
						}
					}
				}
			}
			else {
				for (TempItem = IncludeMaps; TempItem != None; TempItem = TempItem.Next) {
					for (i=0; i<Count; i++) {
						if (TempItem.Data ~= Request.GetVariableNumber("IncludeMapsSelect", i)) {
							TempItem.bJustMoved = true;
							IncludeMaps.MoveElementUp(IncludeMaps, TempItem, MoveCount);
							break;
						}
					}
				}
			}

			UpdateDefaultMaps(GameType, IncludeMaps);
		}
	}

	// Start output here

	Response.Subst("MapListType", MapListType);

	// Generate maplist options
	Response.Subst("MapListOptions", GenerateMapListOptions(GameType, MapListType));

	// Generate map selects
	Response.Subst("ExcludeMapsOptions", GenerateMapListSelect(ExcludeMaps));
	Response.Subst("IncludeMapsOptions", GenerateMapListSelect(IncludeMaps));

	Response.Subst("PostAction", DefaultsMapsPage);
	Response.Subst("GameType", GameType);
	IncludeUHTM(Response,DefaultsMapsPage$".uhtm");
	Response.ClearSubst();
}

function QueryDefaultsRules(SWARequest Request, SWAResponse Response)
{
	local String GameType, FragName, FragLimit, TimeLimit, MaxTeams, FriendlyFire, PlayersBalanceTeams, ForceRespawn;
	local String MaxPlayers, MaxSpectators, WeaponsStay, Tournament;
	local class<GameInfo> GameClass;

	GameType = RequestGameType(Request);
	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));

	MaxPlayers = Request.GetVariable("MaxPlayers", String(class<DeathMatchPlus>(GameClass).Default.MaxPlayers));
	MaxPlayers = String(max(int(MaxPlayers), 0));
	class<DeathMatchPlus>(GameClass).Default.MaxPlayers = int(MaxPlayers);
	Response.Subst("MaxPlayers", MaxPlayers);

	MaxSpectators = Request.GetVariable("MaxSpectators", String(class<DeathMatchPlus>(GameClass).Default.MaxSpectators));
	MaxSpectators = String(max(int(MaxSpectators), 0));
	class<DeathMatchPlus>(GameClass).Default.MaxSpectators = int(MaxSpectators);
	Response.Subst("MaxSpectators", MaxSpectators);

	WeaponsStay = String(class<DeathMatchPlus>(GameClass).Default.bMultiWeaponStay);
	Tournament = String(class<DeathMatchPlus>(GameClass).Default.bTournament);
	if(	class<TeamGamePlus>(GameClass) != None )
		PlayersBalanceTeams = String(class<TeamGamePlus>(GameClass).Default.bPlayersBalanceTeams);

	if(	class<LastManStanding>(GameClass) == None )
		ForceRespawn = String(class<DeathMatchPlus>(GameClass).Default.bForceRespawn);

	if (Request.GetVariable("Apply", "") != "")
	{
		if(	class<TeamGamePlus>(GameClass) != None )
		{
			PlayersBalanceTeams = Request.GetVariable("PlayersBalanceTeams", "false");
			class<TeamGamePlus>(GameClass).Default.bPlayersBalanceTeams = PlayersBalanceTeams ~= "true";
		}
		if(	class<LastManStanding>(GameClass) == None )
		{
			ForceRespawn = Request.GetVariable("ForceRespawn", "false");
			class<DeathMatchPlus>(GameClass).Default.bForceRespawn = bool(ForceRespawn);
		}
		WeaponsStay = Request.GetVariable("WeaponsStay", "false");
		class<DeathMatchPlus>(GameClass).Default.bMultiWeaponStay = bool(WeaponsStay);
		Tournament = Request.GetVariable("Tournament", "false");
		class<DeathMatchPlus>(GameClass).Default.bTournament = bool(Tournament);
	}

	if (WeaponsStay ~= "true") {
		Response.Subst("WeaponsStay", " checked");
	}
	if (Tournament ~= "true") {
		Response.Subst("Tournament", " checked");
	}
	if(	class<LastManStanding>(GameClass) == None )
	{
		if (ForceRespawn ~= "true")
			ForceRespawn = " checked";
		else
			ForceRespawn = "";
		Response.Subst("ForceRespawnSubst", "<label for=\"fForceRespawn\">Force Respawn</label><span><input type=\"checkbox\" id=\"fForceRespawn\" name=\"ForceRespawn\" value=\"true\""$ForceRespawn$"></span>");
	}

	if(	class<TeamGamePlus>(GameClass) != None )
	{
		if (PlayersBalanceTeams ~= "true")
			PlayersBalanceTeams = " checked";
		else
			PlayersBalanceTeams = "";
		Response.Subst("BalanceSubst", "<label for=\"fPlayersBalanceTeams\">Force Balanced Teams</label><span><input type=\"checkbox\" id=\"fPlayersBalanceTeams\" name=\"PlayersBalanceTeams\" value=\"true\""$PlayersBalanceTeams$"></span>");
	}

	if (class<DeathMatchPlus>(GameClass) != None && class<Assault>(GameClass) == None) {
	    	if (class<TeamGamePlus>(GameClass) != None) {
    		FragLimit = Request.GetVariable("FragLimit", String(class<TeamGamePlus>(GameClass).Default.GoalTeamScore));
		FragLimit = String(max(int(FragLimit), 0));
		class<TeamGamePlus>(GameClass).Default.GoalTeamScore = float(FragLimit);
    		FragName = "Max Team Score";
    	}
    	else {
    		FragLimit = Request.GetVariable("FragLimit", String(class<DeathMatchPlus>(GameClass).Default.FragLimit));
    		FragLimit = String(max(int(FragLimit), 0));
    		class<DeathMatchPlus>(GameClass).Default.FragLimit = float(FragLimit);
    		FragName = "Frag Limit";
    	}

    	Response.Subst("FragSubst", "<label for=\"fFragLimit\">"$FragName$"</label><span><input type=\"text\" id=\"fFragLimit\" name=\"FragLimit\" maxlength=\"3\" size=\"3\" value=\""$FragLimit$"\"></span>");

		if(class<LastManStanding>(GameClass) == None)
		{
    		TimeLimit = Request.GetVariable("TimeLimit", String(class<DeathMatchPlus>(GameClass).Default.TimeLimit));
    		TimeLimit = String(max(int(TimeLimit), 0));
			Response.Subst("TimeLimitSubst", "<label for=\"fTimeLimit\">Time Limit</label><span><input type=\"text\" id=\"fTimeLimit\" name=\"TimeLimit\" maxlength=\"3\" size=\"3\" value=\""$TimeLimit$"\"></span>");
			class<DeathMatchPlus>(GameClass).Default.TimeLimit = float(TimeLimit);
		}
	}

	if(class<TeamGamePlus>(GameClass) != None && !ClassIsChildOf( GameClass, class'CTFGame' ) && !ClassIsChildOf( GameClass, class'Assault' ) ) {
   		MaxTeams = Request.GetVariable("MaxTeams", String(class<TeamGamePlus>(GameClass).Default.MaxTeams));
   		MaxTeams = String(max(int(MaxTeams), 0));
   		class<TeamGamePlus>(GameClass).Default.MaxTeams = Min(Max(int(MaxTeams), 2), 4);
		Response.Subst("TeamSubst", "<label for=\"fMaxTeams\">Max Teams</label><span><input type=\"text\" id=\"fMaxTeams\" name=\"MaxTeams\" maxlength=\"2\" size=\"2\" value=\""$MaxTeams$"\"></span>");
	}

	if (class<TeamGamePlus>(GameClass) != None) {
   		FriendlyFire = Request.GetVariable("FriendlyFire", String(class<TeamGamePlus>(GameClass).Default.FriendlyFireScale * 100));
		FriendlyFire = String(min(max(int(FriendlyFire), 0), 100));
   		class<TeamGamePlus>(GameClass).Default.FriendlyFireScale = float(FriendlyFire)/100.0;
		Response.Subst("FriendlyFireSubst", "<label for=\"fFriendlyFire\">Friendly Fire: [0-100]%</label><span><input type=\"text\" id=\"fFriendlyFire\" name=\"FriendlyFire\" maxlength=\"3\" size=\"3\" value=\""$FriendlyFire$"\"></span>");
    }

    Response.Subst("PostAction", DefaultsRulesPage);
   	Response.Subst("GameType", GameType);
    IncludeUHTM(Response,DefaultsRulesPage$".uhtm");
	Response.ClearSubst();

	GameClass.Static.StaticSaveConfig();
}

function QueryDefaultsSettings(SWARequest Request, SWAResponse Response)
{
	local String GameType, UseTranslocator, TickRate;
	local class<GameInfo> GameClass;
	local int GameStyle, GameSpeed, AirControl;

	GameType = RequestGameType(Request);
	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));

	if(Config.bTickrateInSettings)
	{
		if(Level.ConsoleCommand("get UTMenu.UTServerSetupPage bLanPlay") ~= "true" )
			TickRate = Level.ConsoleCommand("get IpDrv.TcpNetDriver LanServerMaxTickRate");
		else
			TickRate = Level.ConsoleCommand("get IpDrv.TcpNetDriver NetServerMaxTickRate");
	}

	if (class<DeathMatchPlus>(GameClass).Default.bMegaSpeed == true)
		GameStyle=1;
	if (class<DeathMatchPlus>(GameClass).Default.bHardCoreMode == true)
		GameStyle+=1;

	switch (Request.GetVariable("GameStyle", String(GameStyle))) {
	case "0":
		class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = false;
		class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = false;
		Response.Subst("Normal", " selected"); break;
		break;
	case "1":
		class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = false;
		class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = true;
		Response.Subst("HardCore", " selected"); break;
	case "2":
		class<DeathMatchPlus>(GameClass).Default.bMegaSpeed = true;
		class<DeathMatchPlus>(GameClass).Default.bHardCoreMode = true;
		Response.Subst("Turbo", " selected"); break;
	}

	GameSpeed = class<DeathMatchPlus>(GameClass).Default.GameSpeed * 100.0;
	AirControl = class<DeathMatchPlus>(GameClass).Default.AirControl * 100.0;
	UseTranslocator = String(class<DeathMatchPlus>(GameClass).Default.bUseTranslocator);

	if (Request.GetVariable("Apply", "") != "") {

		if(Config.bTickRateInSettings)
			TickRate = String(min(max(int(Request.GetVariable("TickRate")), 10), 99));
		GameSpeed = min(max(int(Request.GetVariable("GameSpeed", String(GameSpeed))), 10), 200);
		class<DeathMatchPlus>(GameClass).Default.GameSpeed = GameSpeed / 100.0;

		AirControl = min(max(int(Request.GetVariable("AirControl", String(AirControl))), 0), 100);
		class<DeathMatchPlus>(GameClass).Default.AirControl = AirControl / 100.0;

		UseTranslocator = Request.GetVariable("UseTranslocator", "false");
		class<DeathMatchPlus>(GameClass).Default.bUseTranslocator = bool(UseTranslocator);

		GameClass.Static.StaticSaveConfig();

		Level.ConsoleCommand("set BotPack.DeathMatchPlus MinPlayers "$string(Min(Max(int(Request.GetVariable("MinPlayers", String(0))), 0), 16)));
		if(Config.bTickRateInSettings)
		{
			if(Level.ConsoleCommand("get UTMenu.UTServerSetupPage bLanPlay") ~= "true" )
				Level.ConsoleCommand("set IpDrv.TcpNetDriver LanServerMaxTickRate "$TickRate);
			else
				Level.ConsoleCommand("set IpDrv.TcpNetDriver NetServerMaxTickRate "$TickRate);
		}
	}

	Response.Subst("GameSpeed", String(GameSpeed));
	Response.Subst("AirControl", String(AirControl));
	if (UseTranslocator ~= "true")
		Response.Subst("UseTranslocator", " checked");
	if (Config.bTickrateInSettings)
		Response.Subst("Tickrate", "<label for=\"fTickRate\">TickRate</label><span><input type=\"text\" id=\"fTickRate\" name=\"TickRate\" size=\"3\" maxlength=\"3\" value=\""$TickRate$"\"></span>");
	Response.Subst("MinPlayers", string(DeathMatchPlus(Level.Game).MinPlayers));
	Response.Subst("PostAction", DefaultsSettingsPage);
	Response.Subst("GameType", GameType);
	IncludeUHTM(Response,DefaultsSettingsPage$".uhtm");
	Response.ClearSubst();
}

function QueryDefaultsBots(SWARequest Request, SWAResponse Response)
{
	local String GameType, AutoAdjustSkill, RandomOrder, BalanceTeams, DumbDown;
	local class<GameInfo> GameClass;
	local class<ChallengeBotInfo> BotConfig;
	local int BotDifficulty, MinPlayers;

	GameType = RequestGameType(Request);
	GameClass = class<GameInfo>(DynamicLoadObject(GameType, class'Class'));
	BotConfig = class<DeathMatchPlus>(GameClass).Default.BotConfigType;

	if (Request.GetVariable("Apply", "") != "") {
		BotDifficulty = int(Request.GetVariable("BotDifficulty", String(BotDifficulty)));
		BotConfig.Default.Difficulty = BotDifficulty;

		MinPlayers = min(max(int(Request.GetVariable("MinPlayers", String(MinPlayers))), 0), 16);
		class<DeathMatchPlus>(GameClass).Default.MinPlayers = MinPlayers;

		AutoAdjustSkill = Request.GetVariable("AutoAdjustSkill", "false");
		BotConfig.Default.bAdjustSkill = bool(AutoAdjustSkill);

		RandomOrder = Request.GetVariable("RandomOrder", "false");
		BotConfig.Default.bRandomOrder = bool(RandomOrder);

		if (class<TeamGamePlus>(GameClass) != None) {
			BalanceTeams = Request.GetVariable("BalanceTeams", "false");
			class<TeamGamePlus>(GameClass).Default.bBalanceTeams = bool(BalanceTeams);

			if (class<Domination>(GameClass) != None) {
				DumbDown = Request.GetVariable("DumbDown", "true");
				class<Domination>(GameClass).Default.bDumbDown = bool(Dumbdown);
			}
		}
		BotConfig.Static.StaticSaveConfig();
		GameClass.Static.StaticSaveConfig();
	}

	BotDifficulty = BotConfig.Default.Difficulty;
	MinPlayers = class<DeathMatchPlus>(GameClass).Default.MinPlayers;
	AutoAdjustSkill = String(BotConfig.Default.bAdjustSkill);
	RandomOrder = String(BotConfig.Default.bRandomOrder);

	if (class<TeamGamePlus>(GameClass) != None)
		BalanceTeams = String(class<TeamGamePlus>(GameClass).Default.bBalanceTeams);

	if (class<Domination>(GameClass) != None)
		DumbDown = String(class<Domination>(GameClass).Default.bDumbDown);


	Response.Subst("BotDifficulty"$BotDifficulty, " selected");
	Response.Subst("MinPlayers", String(MinPlayers));

	if (AutoAdjustSkill ~= "true")
		Response.Subst("AutoAdjustSkill", " checked");
	if (RandomOrder ~= "true")
		Response.Subst("RandomOrder", " checked");

	if (class<TeamGamePlus>(GameClass) != None) {
		if (BalanceTeams ~= "true")
			BalanceTeams = " checked";
		else
			BalanceTeams = "";
		Response.Subst("BalanceSubst", "<label for=\"fBalanceTeams\">Bots Balance Teams</label><span><input type=\"checkbox\" id=\"fBalanceTeams\" name=\"BalanceTeams\" value=\"true\""$BalanceTeams$"></span>");

		if (class<Domination>(GameClass) != None) {
			if (DumbDown ~= "false")
				DumbDown = " checked";
			else
				DumbDown = "";
			Response.Subst("DumbDownSubst", "<label for=\"fDumbDown\">Enhanced AI</label><span><input type=\"checkbox\" id=\"fDumbDown\" name=\"DumbDown\" value=\"false\""$DumbDown$"></span>");
		}
	}
	Response.Subst("PostAction", DefaultsBotsPage);
	Response.Subst("GameType", GameType);
	IncludeUHTM(Response,DefaultsBotsPage$".uhtm");
	Response.ClearSubst();
}

function QueryDefaultsIPPolicy(SWARequest Request, SWAResponse Response)
{
	local int i, j;

	if(Request.GetVariable("Update") != "")
	{
		i = int(Request.GetVariable("PolicyNo", "-1"));
		if(i == -1)
			for(i = 0; i<50 && Level.Game.IPPolicies[i] != ""; i++);
		if(i >= 0 && i < 50 && IsValidPolicy(Request.GetVariable("AcceptDeny"), Request.GetVariable("IPMask")))
		{
			Level.Game.IPPolicies[i] = Caps(Request.GetVariable("AcceptDeny"))$","$Request.GetVariable("IPMask");
			Level.Game.SaveConfig();
		}
	}

	if(Request.GetVariable("Delete") != "")
	{
		i = int(Request.GetVariable("PolicyNo", "-1"));

		if(i > 0 && i < 50)
		{
			for(i = i; i<49 && Level.Game.IPPolicies[i] != ""; i++)
				Level.Game.IPPolicies[i] = Level.Game.IPPolicies[i + 1];

			if(i == 49)
				Level.Game.IPPolicies[49] = "";
			Level.Game.SaveConfig();
		}
	}

	IncludeUHTM(Response,DefaultsIPPolicyPage$"-h.uhtm");
	for(i=0; i<50 && Level.Game.IPPolicies[i] != ""; i++)
	{
		j = InStr(Level.Game.IPPolicies[i], ",");
		if(Left(Level.Game.IPPolicies[i], j) ~= "DENY")
		{
			Response.Subst("AcceptCheck", "");
			Response.Subst("DenyCheck", "checked");
		}
		else
		{
			Response.Subst("AcceptCheck", "checked");
			Response.Subst("DenyCheck", "");
		}
		Response.Subst("IPMask", FixHTML(Mid(Level.Game.IPPolicies[i], j+1)));
		Response.Subst("PostAction", DefaultsIPPolicyPage$"?PolicyNo="$string(i));
		// The first entry (normally ACCEPT,*) cannot be deleted, so it gets no Delete button.
		if (i > 0)
			Response.Subst("DeleteButton", "  <input type=\"submit\" name=\"Delete\" value=\"Delete\" class=\"danger\">");
		else
			Response.Subst("DeleteButton", "");
		IncludeUHTM(Response,DefaultsIPPolicyPage$"-d.uhtm", true);
	}
	Response.Subst("PostAction", DefaultsIPPolicyPage);
	IncludeUHTM(Response,DefaultsIPPolicyPage$"-f.uhtm", true);
}

function QueryDefaultsChangePassword(SWARequest Request, SWAResponse Response)
{
  local String NewPassword1;
  local String NewPassword2;

  if (Request.GetVariable("Apply", "") != "")
  {
    NewPassword1 = Request.GetVariable("NewPassword", "");
    NewPassword2 = Request.GetVariable("ConfNewPassword", "");

    if (NewPassword1 == "")
    {
      Response.Subst("Title", "Error");
      Response.Subst("Message", "Blank passwords are not allowed - please retry using a sensible password.");
      IncludeUHTM(Response,MessageUHTM);

    }
    else if (NewPassword1 != NewPassword2)
    {
      Response.Subst("Title", "Error");
      Response.Subst("Message", "Passwords do not match, please retry.");
      IncludeUHTM(Response,MessageUHTM);
    }
    else
    {
      Config.ChangePassword(Request.Username, NewPassword1, true);
      Response.Subst("Title", "Success");
      Response.Subst("Message", "Your password has changed. You are logged out everywhere; <a href=\"/login\">log in again</a> with the new password.");
      IncludeUHTM(Response,MessageUHTM);
    }
  }
  else
  {
    Response.Subst("PostAction", DefaultsChangePasswordPage);
    Response.Subst("Username", FixHTML(Request.Username));
    IncludeUHTM(Response,DefaultsChangePasswordPage$".uhtm");
  }
}


// Web admin users: one table, each row edits one user in place (level, new password,
// delete); a form below adds users. The result is shown above the table.
function QuerySuperAdminWebAdmin(SWARequest Request, SWAResponse Response)
{
	local int i, r;
	local string Rows, Name, Password1, Password2, Notice, Err, Id;

	if (Request.RequestType == Request_POST)
	{
		if (Request.GetVariable("Add2", "") != "")
		{
			Name = Request.GetVariable("Username", "");
			Password1 = Request.GetVariable("Password", "");
			Password2 = Request.GetVariable("ConfPassword", "");
			if (Name == "")
				Err = "Enter a username.";
			else if (Password1 == "")
				Err = "Enter a password. Accounts without a password cannot log in.";
			else if (Password1 != Password2)
				Err = "The passwords do not match.";
			else
			{
				r = Config.AddUser(Name, Password1, int(Request.GetVariable("Priv")));
				if (r == 0)
				{
					Notice = "User "$FixHTML(Name)$" added.";
					log("SWA: "$Request.UserName$"("$Request.ClientIP$") added web admin user '"$Name$"'.");
				}
				else if (r == 1)
					Err = "A user with that name already exists.";
				else if (r == 3)
					Err = "Invalid username: at most 32 characters, no : \" ' < > & or control characters.";
				else
					Err = "There are already 50 users.";
			}
		}
		else if (Request.GetVariable("EditApply", "") != "")
		{
			Name = Request.GetVariable("Username", "");
			Password1 = Request.GetVariable("Password", "");
			Password2 = Request.GetVariable("ConfPassword", "");
			if (!Config.UserExists(Name))
				Err = "No such user exists.";
			else if (Password1 != Password2)
				Err = "The passwords for "$FixHTML(Name)$" do not match.";
			else if (Name == Request.Username && Config.ClampPrivileges(int(Request.GetVariable("Priv"))) < 5)
				Err = "You cannot remove your own super admin level.";
			else
			{
				if (Password1 != "")
					Config.ChangePassword(Name, Password1, true);
				Config.ChangePrivileges(Name, int(Request.GetVariable("Priv")));
				Config.SaveConfig();
				Notice = "User "$FixHTML(Name)$" saved"$Eval(Password1 != "", " with a new password.", ".");
				log("SWA: "$Request.UserName$"("$Request.ClientIP$") changed web admin user '"$Name$"'.");
			}
		}
		else if (Request.GetVariable("Delete", "") != "")
		{
			Name = Request.GetVariable("UserSelect", "");
			if (Name == Request.Username)
				Err = "You cannot delete your own account.";
			else if (Name == "" || Config.DeleteUser(Name) != 0)
				Err = "No such user exists.";
			else
			{
				Notice = "User "$FixHTML(Name)$" deleted.";
				log("SWA: "$Request.UserName$"("$Request.ClientIP$") deleted web admin user '"$Name$"'.");
			}
		}
	}

	for (i = 0; i < 50; i++)
	{
		if (Config.UserList[i] == "")
			continue;
		Name = Config.SelElem(Config.UserList[i], 1);
		Id = "u"$i;
		Rows = Rows$"<tr><td><form id=\""$Id$"\" method=\"post\" action=\"/"$SuperAdminWebAdminPage$"\">"
			$"<input type=\"hidden\" name=\"Username\" value=\""$FixHTML(Name)$"\"><input type=\"hidden\" name=\"UserSelect\" value=\""$FixHTML(Name)$"\"></form>"
			$"<b>"$FixHTML(Name)$"</b>"$Eval(Name == Request.Username, " <span class=\"muted\">(you)</span>", "")$"</td>";
		if (Name == Request.Username)
			Rows = Rows$"<td><input type=\"hidden\" form=\""$Id$"\" name=\"Priv\" value=\"5\">"$PrivilegeName(5)$"</td>";
		else
			Rows = Rows$"<td><select form=\""$Id$"\" name=\"Priv\" aria-label=\"Level of "$FixHTML(Name)$"\">"$PrivOptions(Config.Privileges(Name))$"</select></td>";
		Rows = Rows$"<td><input type=\"password\" form=\""$Id$"\" name=\"Password\" size=\"14\" placeholder=\"unchanged\" autocomplete=\"new-password\" aria-label=\"New password for "$FixHTML(Name)$"\"></td>"
			$"<td><input type=\"password\" form=\""$Id$"\" name=\"ConfPassword\" size=\"14\" autocomplete=\"new-password\" aria-label=\"Confirm the new password\"></td>"
			$"<td class=\"rowactions\"><input type=\"submit\" form=\""$Id$"\" name=\"EditApply\" value=\"Save\">";
		if (Name != Request.Username)
			Rows = Rows$"<input type=\"submit\" form=\""$Id$"\" name=\"Delete\" value=\"Delete\" class=\"danger\" data-confirm=\"Delete the user "$FixHTML(Name)$"?\">";
		Rows = Rows$"</td></tr>";
	}

	if (Err != "")
		Response.Subst("Notice", "<div class=\"block message error\" role=\"alert\">"$Err$"</div>");
	else if (Notice != "")
		Response.Subst("Notice", "<div class=\"block message\" role=\"status\">"$Notice$"</div>");
	else
		Response.Subst("Notice", "");
	Response.Subst("UserRows", Rows);
	Response.Subst("PrivOptions", PrivOptions(1));
	Response.Subst("PostAction", "/"$SuperAdminWebAdminPage);
	IncludeUHTM(Response, SuperAdminWebAdminPage$".uhtm");
}

function string PrivOptions(int Selected)
{
	local int i;
	local string S;

	for (i = 1; i <= 5; i++)
		S = S$"<option value=\""$i$"\""$Eval(i == Selected, " selected", "")$">"$i$" - "$PrivilegeName(i)$"</option>";
	return S;
}

/*function QuerySuperAdminWebAdminConfig(SWARequest Request, SWAResponse Response)
{
	Response.Subst("bEnabled", Level.ConsoleCommand("get UWeb.WebServer bEnabled");
	Response.Subst("MaxConnections", Level.ConsoleCommand("get UWeb.WebServer MaxConnections");
	Response.Subst("ListenPort", Level.ConsoleCommand("get UWeb.WebServer ListenPort");
	Response.Subst("AdminRealm", Config.AdminRealm);
	Response.Subst("ServerURL", Config.ServerURL);
}*/

//--------------------------------------------------------------------------------------------------------

function QuerySuperAdminServer(SWARequest Request, SWAResponse Response)
{
	local String ServerName, AdminName, AdminEmail, MOTDLine1, MOTDLine2, MOTDLine3, MOTDLine4, GamePassword, AdminPassword;
	local bool bDoUplink;
	local string Tickrate, MaxClientRate;

	ServerName = class'Engine.GameReplicationInfo'.default.ServerName;
	AdminName = class'Engine.GameReplicationInfo'.default.AdminName;
	AdminEmail = class'Engine.GameReplicationInfo'.default.AdminEmail;
	MOTDLine1 = class'Engine.GameReplicationInfo'.default.MOTDLine1;
	MOTDLine2 = class'Engine.GameReplicationInfo'.default.MOTDLine2;
	MOTDLine3 = class'Engine.GameReplicationInfo'.default.MOTDLine3;
	MOTDLine4 = class'Engine.GameReplicationInfo'.default.MOTDLine4;
	AdminPassword = Level.ConsoleCommand("get engine.gameinfo AdminPassword");
	GamePassword = Level.ConsoleCommand("get engine.gameinfo GamePassword");
	if(Level.ConsoleCommand("get UTMenu.UTServerSetupPage bLanPlay") ~= "true" )
		TickRate = Level.ConsoleCommand("get IpDrv.TcpNetDriver LanServerMaxTickRate");
	else
		TickRate = Level.ConsoleCommand("get IpDrv.TcpNetDriver NetServerMaxTickRate");

	MaxClientRate = Level.ConsoleCommand("get IpDrv.TcpNetDriver MaxClientRate");
	bDoUplink = class'UdpServerUplink'.default.DoUplink;

	if (Request.GetVariable("Apply", "") != "")
	{
		ServerName = Request.GetVariable("ServerName", "");
		AdminName = Request.GetVariable("AdminName", "");
		AdminEmail = Request.GetVariable("AdminEmail", "");
		MOTDLine1 = Request.GetVariable("MOTDLine1", "");
		MOTDLine2 = Request.GetVariable("MOTDLine2", "");
		MOTDLine3 = Request.GetVariable("MOTDLine3", "");
		MOTDLine4 = Request.GetVariable("MOTDLine4", "");
		bDoUplink = bool(Request.GetVariable("DoUplink", "false"));
		AdminPassword = Request.GetVariable("AdminPassword", "");
		GamePassword = Request.GetVariable("GamePassword", "");
		if (!IsValidGamePassword(AdminPassword) || !IsValidGamePassword(GamePassword))
		{
			DisplayMessage(Response, "Error", "Passwords may not contain spaces, quotes or control characters.");
			return;
		}
		// 469 servers run up to 200 Hz (PlayUnreal: 128); the old limit of 99 lowered it.
		TickRate = String(min(max(int(Request.GetVariable("TickRate")), 10), 200));
		MaxClientRate = String(min(max(int(Request.GetVariable("MaxClientRate")), 1000), 1000000));

		class'Engine.GameReplicationInfo'.Default.ServerName = ServerName;
		class'Engine.GameReplicationInfo'.Default.AdminName = AdminName;
		class'Engine.GameReplicationInfo'.Default.AdminEmail = AdminEmail;
		class'Engine.GameReplicationInfo'.Default.MOTDline1 = MOTDLine1;
		class'Engine.GameReplicationInfo'.Default.MOTDline2 = MOTDLine2;
		class'Engine.GameReplicationInfo'.Default.MOTDline3 = MOTDLine3;
		class'Engine.GameReplicationInfo'.Default.MOTDline4 = MOTDLine4;
		class'Engine.GameReplicationInfo'.Static.StaticSaveConfig();

		class'UdpServerUplink'.default.DoUplink = bDoUplink;
		class'UdpServerUplink'.Static.StaticSaveConfig();

		Level.ConsoleCommand("set engine.gameinfo GamePassword "$GamePassword);
		Level.ConsoleCommand("set engine.gameinfo AdminPassword "$AdminPassword);
		if(Level.ConsoleCommand("get UTMenu.UTServerSetupPage bLanPlay") ~= "true" )
			Level.ConsoleCommand("set IpDrv.TcpNetDriver LanServerMaxTickRate "$TickRate);
		else
			Level.ConsoleCommand("set IpDrv.TcpNetDriver NetServerMaxTickRate "$TickRate);
		Level.ConsoleCommand("set IpDrv.TcpNetDriver MaxClientRate "$MaxClientRate);
	}

	Response.Subst("ServerName", FixHTML(ServerName));
	Response.Subst("AdminName", FixHTML(AdminName));
	Response.Subst("AdminEmail", FixHTML(AdminEmail));
	Response.Subst("MOTDLine1", FixHTML(MOTDLine1));
	Response.Subst("MOTDLine2", FixHTML(MOTDLine2));
	Response.Subst("MOTDLine3", FixHTML(MOTDLine3));
	Response.Subst("MOTDLine4", FixHTML(MOTDLine4));
	Response.Subst("AdminPassword", FixHTML(AdminPassword));
	Response.Subst("GamePassword", FixHTML(GamePassword));
	Response.Subst("TickRate", TickRate);
	Response.Subst("MaxClientRate", MaxClientRate);

	if (bDoUplink)
		Response.Subst("DoUplink", " checked");

	Response.Subst("PostAction", SuperAdminServerPage);
	IncludeUHTM(Response,SuperAdminServerPage$".uhtm");
}

function QuerySuperAdminQuickSetConfig(SWARequest Request, SWAResponse Response)
{
	local int i;
	local class<GameInfo> GameClass;
	local String OptName;
	local String Mutators;
	local String Game;
	local String Tour;
	local String MaxScore;
	local String TimeLimit;
	local String BalanceTeams;
	local String ForceRespawn;
	local String WeaponsStay;
	local String FriendlyFire;
	local String MaxTeams;
	local String GameStyle;
	local String GameSpeed;
	local String AirControl;
	local String Trans;
	local String PlayersSelect;
	local String SpecSelect;
	local string ForcePlayersSet;

	if (Request.GetVariable("Apply", "") != "")
	{
		for (i=0;i<20;i++)
		{
			// GameClass must not carry over from the previous slot; "NotSet" is the blank option.
			GameClass = None;
			Game = "";
			if (Request.GetVariable("GameType"$i) != "" && Request.GetVariable("GameType"$i) != "NotSet")
			{
				Game = ValidateGameType(Request.GetVariable("GameType"$i));
				if (Game != "")
					GameClass = class<GameInfo>(DynamicLoadObject(Game, class'Class', true));
			}
			OptName=ConfigField(Request.GetVariable("Name"$i));
			Mutators=ConfigField(Request.GetVariable("Mutators"$i));
			Tour=ConfigField(Request.GetVariable("Tournament"$i));
			if (class<DeathMatchPlus>(GameClass) != None && class<Assault>(GameClass) == None && Request.GetVariable("GameType"$i) != "")
				MaxScore=String(max(int(Request.GetVariable("MaxScore"$i)), 0));
			else
				MaxScore="N/A";
			if(class<LastManStanding>(GameClass) == None && Request.GetVariable("GameType"$i) != "")
				TimeLimit=String(max(int(Request.GetVariable("TimeLimit"$i)), 0));
			else
				TimeLimit="N/A";
			if(class<TeamGamePlus>(GameClass) != None && Request.GetVariable("GameType"$i) != "")
			{
				if(Caps(Request.GetVariable("BalanceTeams"$i))!="TRUE")
					BalanceTeams="false";
				else
					BalanceTeams=Request.GetVariable("BalanceTeams"$i);
				FriendlyFire=String(min(max(int(Request.GetVariable("FriendlyFire"$i)), 0), 100));
			}
			else
			{
				BalanceTeams="false";
				FriendlyFire="N/A";
			}
			if(Caps(Request.GetVariable("ForceRespawn"$i))!="TRUE")
				ForceRespawn="false";
			else
				ForceRespawn=Request.GetVariable("ForceRespawn"$i);
			if(Caps(Request.GetVariable("WeaponsStay"$i))!="TRUE")
				WeaponsStay="false";
			else
				WeaponsStay=Request.GetVariable("WeaponsStay"$i);
			if((class<TeamGamePlus>(GameClass) != None && !ClassIsChildOf( GameClass, class'CTFGame' ) && !ClassIsChildOf( GameClass, class'Assault' )) && Request.GetVariable("GameType"$i) != "")
				MaxTeams=String(Min(Max(int(Request.GetVariable("MaxTeams"$i)), 2), 4));
			else
				MaxTeams="N/A";
			GameStyle=ConfigField(Request.GetVariable("GameStyle"$i));
			GameSpeed=String(min(max(int(Request.GetVariable("GameSpeed"$i)), 10), 200));
			AirControl=String(min(max(int(Request.GetVariable("AirControl"$i)), 0), 100));
			if(Caps(Request.GetVariable("Trans"$i))!="TRUE")
				Trans="false";
			else
				Trans=Request.GetVariable("Trans"$i);
			PlayersSelect=String(min(max(int(Request.GetVariable("PlayersSelect"$i)), 0), 32));
			SpecSelect=ConfigField(Request.GetVariable("SpecSelect"$i));
			ForcePlayersSet=ConfigField(Request.GetVariable("ForcePlayersSet"$i));
			Config.QuickSetConf[i]=OptName$":"$Mutators$":"$Game$":"$Tour$":"$MaxScore$":"$TimeLimit$":"$BalanceTeams$":"$ForceRespawn$":"$WeaponsStay$":"$FriendlyFire$":"$MaxTeams$":"$GameStyle$":"$GameSpeed$":"$AirControl$":"$Trans$":"$PlayersSelect$":"$SpecSelect$":"$ForcePlayersSet;
		}
		Config.SaveConfig();
	}
	for (i=0;i<20;i++)
	{
		Response.Subst("Name"$i, Config.SelElem(Config.QuickSetConf[i], 1));
		if(Config.SelElem(Config.QuickSetConf[i], 3)!="")
			Response.Subst("GameType"$i, "<select name=\"GameType"$i$"\"><option value=\"NotSet\"></option>"$GenerateGameTypeOptions(Config.SelElem(Config.QuickSetConf[i], 3))$"</select>");
		else
			Response.Subst("GameType"$i, "<select name=\"GameType"$i$"\"><option value=\"\" selected></option>"$GenerateGameTypeOptions("")$"</select>");
		Response.Subst("Mutators"$i, Config.SelElem(Config.QuickSetConf[i], 2));
		if(Config.SelElem(Config.QuickSetConf[i], 4)~="True")
			Response.Subst("Tournament"$i, " checked");
		else
			Response.Subst("Tournament"$i, "");
		Response.Subst("MaxScore"$i, Config.SelElem(Config.QuickSetConf[i], 5));
		Response.Subst("TimeLimit"$i, Config.SelElem(Config.QuickSetConf[i], 6));
		if(Config.SelElem(Config.QuickSetConf[i], 7)~="True")
			Response.Subst("BalanceTeams"$i, " checked");
		else
			Response.Subst("BalanceTeams"$i, "");
		if(Config.SelElem(Config.QuickSetConf[i], 8)~="True")
			Response.Subst("ForceRespawn"$i, " checked");
		else
			Response.Subst("ForceRespawn"$i, "");
		if(Config.SelElem(Config.QuickSetConf[i], 9)~="True")
			Response.Subst("WeaponsStay"$i, " checked");
		else
			Response.Subst("WeaponsStay"$i, "");
		if(Config.SelElem(Config.QuickSetConf[i], 10)!="N/A")
			Response.Subst("FriendlyFire"$i, String(min(max(int(Config.SelElem(Config.QuickSetConf[i], 10)), 0), 100)));
		else
			Response.Subst("FriendlyFire"$i, "N/A");
		Response.Subst("MaxTeams"$i, Config.SelElem(Config.QuickSetConf[i], 11));
		switch (Config.SelElem(Config.QuickSetConf[i], 12))
		{
			case "0":
				Response.Subst("Normal"$i, " selected"); break;
			case "1":
				Response.Subst("HardCore"$i, " selected"); break;
			case "2":
				Response.Subst("Turbo"$i, " selected"); break;
			default:
				Response.Subst("HardCore"$i, " selected"); break;
		}
		Response.Subst("GameSpeed"$i, Config.SelElem(Config.QuickSetConf[i], 13));
		Response.Subst("AirControl"$i, Config.SelElem(Config.QuickSetConf[i], 14));
		if(Config.SelElem(Config.QuickSetConf[i], 15)~="True")
			Response.Subst("Trans"$i, " checked");
		else
			Response.Subst("Trans"$i, "");
		Response.Subst("PlayersSelect"$i, Config.SelElem(Config.QuickSetConf[i], 16));
		switch (Config.SelElem(Config.QuickSetConf[i], 17))
		{
			case "0":
				Response.Subst("0SpecSelect"$i, "selected"); break;
			case "1":
				Response.Subst("1SpecSelect"$i, "selected"); break;
			case "2":
				Response.Subst("2SpecSelect"$i, "selected"); break;
			case "3":
				Response.Subst("3SpecSelect"$i, "selected"); break;
			case "4":
				Response.Subst("4SpecSelect"$i, "selected"); break;
		}
		if(i!=0)
		{
			if(Config.SelElem(Config.QuickSetConf[i], 18)~="True")
				Response.Subst("ForcePlayersSet"$i, " checked");
			else
				Response.Subst("ForcePlayersSet"$i, "");
		}
	}
	Response.Subst("ApplyButton", "<input type=\"submit\" name=\"Apply\" value=\"Apply\">");
	Response.Subst("PostAction", SuperAdminQuickSetConfigPage);
	IncludeUHTM(Response,SuperAdminQuickSetConfigPage$".uhtm");
}

function QueryBanlist(SWARequest Request, SWAResponse Response)
{
	local int	i, j, RangeBase;
	local int	PolicyCount, MaxBans;

	MaxBans = ArrayCount(opconf.IPPolicies);

	// A range button is pressed - set the appropriate range
	if (Request.GetVariable("B1", "") != "")
		BanPage = 0;
	else if (Request.GetVariable("B51", "") != "")
		BanPage = 1;
	else if (Request.GetVariable("B101", "") != "")
		BanPage = 2;
	else if (Request.GetVariable("B151", "") != "")
		BanPage = 3;
	else if (Request.GetVariable("B201", "") != "")
		BanPage = 4;


	// A policy is changed
	if (Request.GetVariable("Update") != "")
		{
		i = int(Request.GetVariable("PolicyNo", "-1"));
		if (i == -1)
			for (i = 0; i < MaxBans && opconf.IPPolicies[i] != ""; i++);
		if (i >= 0 && i < MaxBans && IsValidPolicy(Request.GetVariable("AcceptDeny"), Request.GetVariable("IPMask")))
		{
			opconf.IPPolicies[i] = Caps(Request.GetVariable("AcceptDeny"))$","$Request.GetVariable("IPMask");
			opconf.SaveConfig();
		}
		}

	// A policy is deleted
	if (Request.GetVariable("Delete") != "")
		{
		i = int(Request.GetVariable("PolicyNo", "-1"));

		if (i > 0 && i < MaxBans)
			{
			for (i = i; i < MaxBans-1 && opconf.IPPolicies[i] != ""; i++)
				opconf.IPPolicies[i] = opconf.IPPolicies[i + 1];

			if (i == MaxBans-1)
				opconf.IPPolicies[i] = "";
			opconf.SaveConfig();
			}
		}

	// Change the range select buttons so
	// only ranges with policies in can be selected

	for (i = 0; i < MaxBans; i += 50)
		{
		if (opconf.IPPolicies[i] != "")
			Response.Subst("B"$i$"type", "submit");
		else
			{
			if (BanPage > i / 50)	// make sure page is within range
				BanPage = i / 50;
			Response.Subst("B"$i$"type", "hidden");
			}
		}

	// Show the IPPolicies for the page range
	RangeBase = BanPage * 50;
	Response.Subst("Range", RangeBase + 1 $ " - " $ RangeBase + 50);
	IncludeUHTM(Response,"ob_ippolicy-h.uhtm");
	for (i = RangeBase; i < RangeBase + 50 && opconf.IPPolicies[i] != ""; i++)
		{
		j = InStr(opconf.IPPolicies[i], ",");
		if (Left(opconf.IPPolicies[i], j) ~= "DENY")
			{
			Response.Subst("AcceptCheck", "");
			Response.Subst("DenyCheck", "checked");
			}
		else
			{
			Response.Subst("AcceptCheck", "checked");
			Response.Subst("DenyCheck", "");
			}
		Response.Subst("IPMask", FixHTML(Mid(opconf.IPPolicies[i], j + 1)));
		Response.Subst("PostAction", "banlist?PolicyNo="$string(i));
		IncludeUHTM(Response,"ob_ippolicy-d.uhtm", true);
		}
	Response.Subst("PostAction", "banlist");
	// Only put a 'new' button on the last page
	if ((BanPage + 1 >= MaxBans / 50) || (opconf.IPPolicies[(BanPage + 1) * 50] == ""))
		IncludeUHTM(Response,"ob_ippolicy-s.uhtm", true);
	IncludeUHTM(Response,"ob_ippolicy-f.uhtm", true);
}

function QueryDynalist(SWARequest Request, SWAResponse Response)
{
	local int	i, j, k, RangeBase;
	local int	PolicyCount, MaxBans;
	local int	DayTemp, MapTemp;
	local string IPTemp, comment;

	MaxBans = ArrayCount(opconf.DynaPolicies);

	// A range button is pressed - set the appropriate range
	if (Request.GetVariable("B1", "") != "")
		DynaPage = 0;
	else if (Request.GetVariable("B51", "") != "")
		DynaPage = 1;
	else if (Request.GetVariable("B101", "") != "")
		DynaPage = 2;
	else if (Request.GetVariable("B151", "") != "")
		DynaPage = 3;
	else if (Request.GetVariable("B201", "") != "")
		DynaPage = 4;


	// A policy is changed
	if (Request.GetVariable("Update") != "")
		{
		i = int(Request.GetVariable("PolicyNo", "-1"));
		if (i == -1)
			for (i = 0; i < MaxBans && opconf.DynaPolicies[i] != ""; i++);
		if (i >= 0 && i < MaxBans)
			{
			opconf.ExtractDynaData(i, IPTemp, DayTemp, MapTemp, comment);
			DayTemp = Clamp(int(Request.GetVariable("DayCount")), 0, 999);
			MapTemp = Clamp(int(Request.GetVariable("MapCount")), 0, 999);
			comment = SanitizeBanText(Request.GetVariable("Reason"))$":"$SepRight(comment);

			IPTemp = Request.GetVariable("IPMask");
			if (IPTemp != "" && IsValidIPMask(IPTemp))
			    {
			    if (comment != "")
			        opconf.DynaPolicies[i] = IPTemp$"="$DayTemp$","$MapTemp$"!"$comment;
			    else
			        opconf.DynaPolicies[i] = IPTemp$"="$DayTemp$","$MapTemp;
			    }
			}
		opconf.SaveConfig();
		}

	// A policy is deleted
	if (Request.GetVariable("Delete") != "")
		{
		i = int(Request.GetVariable("PolicyNo", "-1"));

		if (i >= 0 && i < MaxBans)
			{
			for (i = i; i < MaxBans-1 && opconf.DynaPolicies[i] != ""; i++)
				opconf.DynaPolicies[i] = opconf.DynaPolicies[i + 1];

			if (i == MaxBans-1)
				opconf.DynaPolicies[i] = "";
			opconf.SaveConfig();
			}
		}

	// Change the range select buttons so
	// only ranges with policies in can be selected

	for (i = 0; i < MaxBans; i += 50)
		{
		if (opconf.DynaPolicies[i] != "")
			Response.Subst("B"$i$"type", "submit");
		else
			{
			if (DynaPage > i / 50)	// make sure page is within range
				DynaPage = i / 50;
			Response.Subst("B"$i$"type", "hidden");
			}
		}

	// Show the IPPolicies for the page range
	RangeBase = DynaPage * 50;
	Response.Subst("Range", RangeBase + 1 $ " - " $ RangeBase + 50);
	Response.Subst("NickLog", "Nick");
	IncludeUHTM(Response,"ob_ipdyna-h.uhtm");
	for (i = RangeBase; i < RangeBase + 50 && opconf.DynaPolicies[i] != ""; i++)
		{
		opconf.ExtractDynaData(i, IPTemp, DayTemp, MapTemp, comment);
		Response.Subst("IPMask", FixHTML(IPTemp));
		Response.Subst("DayCount", string(DayTemp));
		Response.Subst("MapCount", string(MapTemp));
		Response.Subst("Reason", FixHTML(SepLeft(comment)));
		Response.Subst("Ident", FixHTML(SepRight(comment)));
		Response.Subst("PostAction", "dynalist?PolicyNo="$string(i));
		IncludeUHTM(Response,"ob_ipdyna-d.uhtm", true);
		}
	Response.Subst("PostAction", "dynalist");
	// Only put a 'new' button on the last page
	if ((DynaPage + 1 >= MaxBans / 50) || (opconf.DynaPolicies[(DynaPage + 1) * 50] == ""))
		{
		Response.Subst("DayCount", string(opconf.DefBanDays));
		Response.Subst("MapCount", string(opconf.DefBanMaps));
		Response.Subst("Comment", "");
		IncludeUHTM(Response,"ob_ipdyna-s.uhtm", true);
		}
	IncludeUHTM(Response,"ob_ipdyna-f.uhtm", true);
}

function QueryOptions(SWARequest Request, SWAResponse Response)
{
	local bool CleanList, KickPLayers, Announce, SysIni;
	local string sAutoPass, sAutoName;

	// Load up the current options
	CleanList = opconf.bCleanPolicy;
	KickPlayers = opconf.bKickPlayers;
	Announce = opconf.bAnnounceKicks;
	SysIni = opmain.bUseSystemIni;
	sAutoPass = opconf.sAutoPass;
	sAutoName = opconf.sAutoName;

	// An update...
	if (Request.GetVariable("Apply", "") != "")
		{
		// Get the web page options data
		CleanList = bool(Request.GetVariable("DoCleanup", "false"));
		KickPlayers = bool(Request.GetVariable("DoKick", "false"));
		Announce = bool(Request.GetVariable("DoAnnounce", "false"));
		sAutoPass = Request.GetVariable("AutoPass", "");
		sAutoName = Request.GetVariable("AutoName", "");
		if (!opmain.bLockIniChoice)	// Don't change ini file if not allowed
			SysIni = bool(Request.GetVariable("UseSysIni", "false"));

		// Change the application options
		opconf.bCleanPolicy = CleanList;
		opconf.bKickPlayers = KickPlayers;
		opconf.bAnnounceKicks = Announce;
		opconf.sAutoPass = sAutoPass;
		opconf.sAutoName = sAutoName;
		if (!opmain.bLockIniChoice)	// Don't change ini file if not allowed
			{
			opmain.bUseSystemIni = SysIni;
			opmain.SaveConfig();
			}

		opconf.SaveConfig();
		}

	// Set the display to match the current options
	if (CleanList)
		Response.Subst("DoCleanup", " checked");
	if (KickPLayers)
		Response.Subst("DoKick", " checked");
	if (Announce)
		Response.Subst("DoAnnounce", " checked");
	if (SysIni)
		Response.Subst("UseSysIni", " checked");
	Response.Subst("AutoName", sAutoName);
	Response.Subst("AutoPass", sAutoPass);

	if (opmain.bLockIniChoice)
		Response.Subst("IniLock", "Locked");
	else
		Response.Subst("IniLock", "Requires level restart");

	Response.Subst("PostAction", OPBanOptions);
	IncludeUHTM(Response,"ob_options.uhtm");
}

// Gah! Generic mass edit list function. UT doesn't allow passing of a
// static array to functions, so we have to work out which one it is and
// explicitly specify it every time...
function QueryEditList(SWARequest Request, SWAResponse Response, bool bIsOPList)
{
	local int 		i, j, k, ItemCnt, MaxCount, DropCount;
	local string 	EditListData, ItemData, policy, ListName;

	if (bIsOPList)
		{
		ListName = "OPBan";
		MaxCount = ArrayCount(opconf.IPPolicies);
		}
	else
		{
		ListName = "UT";
		MaxCount = ArrayCount(Level.Game.IPPolicies);
		}

	if (Request.GetVariable("Apply", "") != "")
		{
		// Make sure the browser does scripting
		if (Request.GetVariable("Check", "") != "")
			{
			Response.Subst("SmallTitle", "Mass Edit Problem");
			Response.Subst("Title", "No browser scripting available");
			Response.Subst("Message", "You were told, but would you listen? Hahaha...bonk");
			IncludeUHTM(Response,"message.uhtm");
			return;
			}

		ItemCnt = Request.GetVariableCount("AddressData");

		j = 1;	// Start at policy 1 (0 is always ACCEPT/DENY *)
		DropCount = ItemCnt;
		for (i = 0; i < ItemCnt; i++)
			{
			if (j >= MaxCount)	// don't overrun policy store
				break;

			// Get next policy to store
			ItemData = Request.GetVariableNumber("AddressData", ItemCnt - 1 - i);
			// check it really is a policy
			k = InStr(ItemData, ",");
			if (k == -1)	// No ',' means invalid policy
				{
				DropCount--;
				continue;
				}
			policy = Left(ItemData, k);		// Get policy type
			if ((policy ~= "DENY") || (policy ~= "ACCEPT"))
				{
				// good policy so store and point to next
				if (bIsOPList)
					opconf.IPPolicies[j] = ItemData;
				else
					Level.Game.IPPolicies[j] = ItemData;
				j++;
				}
			else
				DropCount--;
			}

		DropCount = DropCount + 1 - j;	// Remember if any got dropped
		ItemCnt = j - 1;	// Fix real count (excluding invalid items)

		// Clear the rest of the policies (if any)
		while (j < MaxCount)
			{
			if (bIsOPList)
				opconf.IPPolicies[j] = "";
			else
				Level.Game.IPPolicies[j] = "";
			j++;
			}
		if (bIsOPList)
			opconf.SaveConfig();
		else
			Level.Game.SaveConfig();


		Response.Subst("Title", ListName$" policy");
		if (DropCount > 0)
			{
			Response.Subst("SmallTitle", "Mass Edit Problem");
			Response.Subst("Message", "Last "$DropCount$" items dropped - only "$MaxCount - 1$" allowed.");
			Log(opconf.sApplication$": "$ListName$" policy updated with "$ItemCnt$" items ("$DropCount$" dropped).");
			}
		else
			{
			Response.Subst("SmallTitle", "Mass Edit");
			Response.Subst("Message", ItemCnt $" policies stored, space for " $(MaxCount - 1) - ItemCnt$" left.");
			Log(opconf.sApplication$": "$ListName$" policy updated with "$ItemCnt$" items.");
			}
		IncludeUHTM(Response,"message.uhtm");
		return;
		}

	if (bIsOPList)
		{
		for (i = 1; i < MaxCount && opconf.IPPolicies[i] != ""; i++)
			EditListData = EditListData$Chr(13)$opconf.IPPolicies[i];
		}
	else
		{
		for (i = 1; i < MaxCount && Level.Game.IPPolicies[i] != ""; i++)
			EditListData = EditListData$Chr(13)$Level.Game.IPPolicies[i];
		}


	Response.Subst("SmallTitle", "Mass Edit");
	Response.Subst("Title", ListName$" Policy");
	Response.Subst("EditListData", FixHTML(EditListData));
	if (bIsOPList)
		Response.Subst("PostAction", "editOPlist");
	else
		Response.Subst("PostAction", "editUTlist");
	IncludeUHTM(Response,"ob_editlist.uhtm");
}

function QueryEditDynaList(SWARequest Request, SWAResponse Response)
{
    local int        i, j, k, ItemCnt, MaxCount, DropCount;
    local string     EditListData, ItemData;

    MaxCount = ArrayCount(opconf.DynaPolicies);

    if (Request.GetVariable("Apply", "") != "")
        {
		// Make sure the browser does scripting
		if (Request.GetVariable("Check", "") != "")
			{
			Response.Subst("SmallTitle", "Mass Edit Problem");
			Response.Subst("Title", "No browser scripting available");
			Response.Subst("Message", "You were told, but would you listen? Hahaha...bonk");
			IncludeUHTM(Response,"message.uhtm");
			return;
			}

		ItemCnt = Request.GetVariableCount("AddressData");

		j = 0;
		DropCount = ItemCnt;
		for (i = 0; i < ItemCnt; i++)
		    {
		    if (j >= MaxCount)
                break;

            ItemData = Request.GetVariableNumber("AddressData", ItemCnt - 1 - i);
            if (InStr(ItemData,"=") == -1)
                {
                DropCount--;
                continue;
                }
            if (InStr(ItemData,",") == -1)
                {
                DropCount--;
                continue;
                }
            opconf.DynaPolicies[j] = ItemData;
            j++;
		    }

        DropCount = DropCount - j;
        ItemCnt = j;

        while (j < MaxCount)
            {
            opconf.DynaPolicies[j] = "";
            j++;
            }

        opconf.SaveConfig();

		Response.Subst("Title", "Dynamic policy");
		if (DropCount > 0)
			{
			Response.Subst("SmallTitle", "Mass Edit Problem");
			Response.Subst("Message", "Last "$DropCount$" items dropped - only "$MaxCount$" allowed.");
			Log(opconf.sApplication$": Dynamic policy updated with "$ItemCnt$" items ("$DropCount$" dropped).");
			}
		else
			{
			Response.Subst("SmallTitle", "Mass Edit");
			Response.Subst("Message", ItemCnt $" policies stored, space for " $(MaxCount) - ItemCnt$" left.");
			Log(opconf.sApplication$": Dynamic policy updated with "$ItemCnt$" items.");
			}
		IncludeUHTM(Response,"message.uhtm");
		return;
        }

    for (i = 0; i < MaxCount && opconf.DynaPolicies[i] != ""; i++)
        EditListData = EditListData$Chr(13)$opconf.DynaPolicies[i];

    Response.Subst("SmallTitle", "Mass Edit");
    Response.Subst("Title", "Dynamic Policy");
    Response.Subst("EditListData", FixHTML(EditListData));
    Response.Subst("PostAction", EditDynaList);
    IncludeUHTM(Response,"ob_editdyna.uhtm");
}


// The generic automatons 'page' for the mass edit list
// Again, because UT doesn't allow static array passing,
// selecting and specifying the list is done every time
// it's accessed.
function QueryAutoList(SWARequest Request, SWAResponse Response, bool bIsOPList)
{
	local int 		i, j, k, ItemCnt, MaxCount, DropCount;
	local string 	EditListData, ItemData, policy, ListName;

	if (bIsOPList)
		{
		ListName = "OP";
		MaxCount = ArrayCount(opconf.IPPolicies);
		}
	else
		{
		ListName = "UT";
		MaxCount = ArrayCount(Level.Game.IPPolicies);
		}

	if (Request.GetVariable("Apply", "") != "")
		{
		ItemCnt = Request.GetVariableCount("AddressData");

		j = 1;	// Start at policy 1 (0 is always ACCEPT/DENY *)
		DropCount = ItemCnt;
		for (i = 0; i < ItemCnt; i++)
			{
			if (j >= MaxCount)	// don't overrun policy store
				break;

			// Get next policy to store
			ItemData = Request.GetVariableNumber("AddressData", ItemCnt - 1 - i);
			// check it really is a policy
			k = InStr(ItemData, ",");
			if (k == -1)	// No ',' means invalid policy
				{
				DropCount--;
				continue;
				}
			policy = Left(ItemData, k);		// Get policy type
			if ((policy ~= "DENY") || (policy ~= "ACCEPT"))
				{
				// good policy so store and point to next
				if (bIsOPList)
					opconf.IPPolicies[j] = ItemData;
				else
					Level.Game.IPPolicies[j] = ItemData;
				j++;
				}
			else
				DropCount--;
			}

		DropCount = DropCount + 1 - j;	// Remember if any got dropped
		ItemCnt = j - 1;	// Fix real count (excluding invalid items)

		// Clear the rest of the policies (if any)
		while (j < MaxCount)
			{
			if (bIsOPList)
				opconf.IPPolicies[j] = "";
			else
				Level.Game.IPPolicies[j] = "";
			j++;
			}
		if (bIsOPList)
			opconf.SaveConfig();
		else
			Level.Game.SaveConfig();

		if (DropCount > 0)
			Log(opconf.sApplication$": "$ListName$" policy auto-updated with "$ItemCnt$" items ("$DropCount$" dropped).");
		else
			Log(opconf.sApplication$": "$ListName$" policy auto-updated with "$ItemCnt$" items.");
		}

	Response.SendText(opconf.sApplication$Chr(13)$opconf.sVersion$Chr(13)$ListName);

	if (bIsOPList)
		{
		for (i = 1; i < MaxCount && opconf.IPPolicies[i] != ""; i++)
			Response.SendText(opconf.IPPolicies[i]);
		}
	else
		{
		for (i = 1; i < MaxCount && Level.Game.IPPolicies[i] != ""; i++)
			Response.SendText(Level.Game.IPPolicies[i]);
		}

	Response.SendText("---");
}

// The automatons 'page' for the dynamic ban list.
function QueryAutoDynaList(SWARequest Request, SWAResponse Response)
{
    local int        Maxcount, DropCount, ItemCnt, i, j, k;
    local string     EditListData, ItemData, Policy;

    MaxCount = ArrayCount(opconf.DynaPolicies);

    if (request.GetVariable("Apply", "") != "")
        {
        ItemCnt = Request.GetVariableCount("AddressData");

        j = 0;    // Dynamic ban list starts at 0
        DropCount = ItemCnt;
        for (i = 0; i < ItemCnt; i++)
            {
            if (j >= MaxCount)   // Don't go past the end!
                break;

            // Next item to store
            ItemData = Request.GetVariableNumber("AddressData", ItemCnt - 1 - i);
            // Check it's at least notionally valid - contains the '=' and ','
            // delimeters ('!' is optional)
            if (InStr(ItemData,"=") == -1)
                {
                DropCount--;
                continue;
                }
            if (InStr(ItemData,",") == -1)
                {
                DropCount--;
                continue;
                }
            // Probably OK if we get here, so store it verbatim
            opconf.DynaPolicies[j] = ItemData;
            j++;
            }

        DropCount = DropCount - j;    // Remember if any got dropped
        ItemCnt = j;                  // Fix real count (excl invalid items)

        // Clear the rest of the array
        while (j < MaxCount)
            {
            opconf.DynaPolicies[j] = "";
            j++;
            }

        // Commit the changes
        opconf.SaveConfig();

        if (DropCount > 0)
            Log(opconf.sApplication$": Dynamic ban list auto-updated with "$ItemCnt$" items ("$DropCount$" dropped).");
        }

    Response.SendText(opconf.sApplication$Chr(13)$opconf.sVersion$Chr(13)$"Dynamic");

    for (i = 0; i < MaxCount && opconf.DynaPolicies[i] != ""; i++)
        Response.SendText(opconf.DynaPolicies[i]);

    Response.SendText("---");
}

function string GetStrTime(int Time)
{
	local int m;
	local int s;

	m = (Time % 3600) / 60;
	s = Time % 60;

	if(s<10)
		return string(m)$":0"$string(s);
	else
		return string(m)$":"$string(s);
}

function string FixHTML(string Str)
{
	return ReplaceText(ReplaceText(ReplaceText(ReplaceText(ReplaceText(Str, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;"), "'", "&#39;");
}

//-----------------------------------------------------------------------------
// Page layout (SWA2): one page per view, no frames. Every page gets the top bar,
// the HUD strip (map, game, time, players) and the navigation; templates in
// Web/ hold only the page content.
//-----------------------------------------------------------------------------

// Sends a template wrapped in the layout. "-h" templates open the layout, "-f"
// templates close it (pages built from fragments); bNoHeader = fragment in between.
function IncludeUHTM(SWAResponse Response, string file, optional bool bNoHeader)
{
	local bool bBare;

	bBare = (file == (CurrentConsoleLogPage$".uhtm"));
	if (!bNoHeader)
		PageStart(Response, bBare);
	Response.IncludeUHTM(file);
	if (bBare)
		Response.SendText("</body></html>");
	else if (Right(file, 7) == "-f.uhtm" || (!bNoHeader && Right(file, 7) != "-h.uhtm"))
		PageEnd(Response);
}

function PageStart(SWAResponse Response, optional bool bBare)
{
	local string Page;

	Page = CurrentPageName();
	Response.SendText("<!DOCTYPE html>"$Chr(13)$Chr(10)$"<html lang=\"en\"><head><meta charset=\"iso-8859-1\">"
		$"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
		$"<title>"$FixHTML(PageTitle(Page))$" - "$FixHTML(Config.AdminRealm)$"</title>"
		$"<link rel=\"icon\" href=\"/favicon.ico\"><link rel=\"stylesheet\" href=\"/swa2.css\">"
		$"<script>try{if(localStorage.getItem('swa2-theme')=='light')document.documentElement.setAttribute('data-theme','light');}catch(e){}</script></head>");
	if (bBare)
	{
		Response.SendText("<body class=\"bare\">");
		return;
	}
	Response.SendText("<body><header class=\"topbar\"><button type=\"button\" class=\"menubtn\" id=\"menubtn\" aria-expanded=\"false\" aria-controls=\"nav\">Menu</button>"
		$"<div class=\"server\"><span class=\"name\">"$FixHTML(ServerName())$"</span><small>"$FixHTML(ServerAddress())$" &nbsp;SuperWebAdmin2</small></div>"
		$"<div class=\"right\"><button type=\"button\" id=\"theme\" class=\"icon\" title=\"Switch to light mode\" aria-label=\"Switch to light mode\"><svg class=\"i-sun\" viewBox=\"0 0 24 24\" aria-hidden=\"true\"><circle cx=\"12\" cy=\"12\" r=\"4.5\"/>"
		$"<path d=\"M12 1.5v3M12 19.5v3M1.5 12h3M19.5 12h3M4.6 4.6l2.1 2.1M17.3 17.3l2.1 2.1M4.6 19.4l2.1-2.1M17.3 6.7l2.1-2.1\"/></svg>"
		$"<svg class=\"i-moon\" viewBox=\"0 0 24 24\" aria-hidden=\"true\"><path d=\"M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z\"/></svg></button>"
		$"<span class=\"user\"><b>"$FixHTML(CurRequest.Username)$"</b> <span class=\"lvl\">"$PrivilegeName(Config.Privileges(CurRequest.Username))$"</span>"
		$Eval(Config.Privileges(CurRequest.Username) > 0, " <a class=\"btn\" href=\"/"$DefaultsChangePasswordPage$"\">Change password</a>", "")
		$" <a class=\"btn logout\" href=\"/logout?u="$FixHTML(CurRequest.Username)$"\">Log out</a></span></div></header>");
	Response.SendText(HUDStrip());
	Response.SendText("<div class=\"shell\">"$BuildNav(Page)$"<div class=\"content\">");
	// the Defaults pages start with a game type row; their panel takes the same width (CSS main.gt)
	if (Page == DefaultsMapsPage || Page == DefaultsRulesPage || Page == DefaultsSettingsPage || Page == DefaultsBotsPage)
		Response.SendText("<main class=\"gt\"><h1>"$FixHTML(PageTitle(Page))$"</h1>"
			$"<form method=\"get\" action=\"/"$Page$"\" class=\"actions\" style=\"margin:0 0 14px\"><label for=\"gt\" class=\"muted\">Game type</label>"
			$"<select id=\"gt\" name=\"GameType\">"$GenerateGameTypeOptions(RequestGameType(CurRequest))$"</select><input type=\"submit\" value=\"Show\"></form>");
	// Players: Refresh next to the heading (a reload link that keeps the sort order)
	else if (Page == CurrentPlayersPage)
		Response.SendText("<main><div class=\"pagehead\"><h1>"$FixHTML(PageTitle(Page))$"</h1>"
			$"<a class=\"btn\" href=\"/"$CurrentPlayersPage$"?Sort="$PlayersSort(CurRequest)$"\">Refresh</a></div>");
	else
		Response.SendText("<main><h1>"$FixHTML(PageTitle(Page))$"</h1>");
}

function PageEnd(SWAResponse Response)
{
	local string S;

	S = "SuperWebAdmin2 "$SWAVersion$", based on SuperWebAdmin 0.97b by [es]Rush.";
	if (opmain != None)
		S = S$" OPBan is running.";
	if (bIpToCountry)
		S = S$" Country flags from IpToCountry.";
	Response.SendText("</main><footer>"$S$"</footer></div></div>"$RestartDialog()$PageScript()$"</body></html>");
}

// The page name of the current request ("current_players"), "" for the root.
function string CurrentPageName()
{
	if (CurRequest == None)
		return "";
	return Mid(CurRequest.URI, 1);
}

function string PageTitle(string Page)
{
	switch (Page)
	{
	case CurrentPlayersPage:          return "Players";
	case CurrentGamePage:             return "Change map";
	case CurrentMutatorsPage:         return "Mutators";
	case CurrentRulesPage:            return "Rules";
	case CurrentConsolePage:          return "Console";
	case CurrentConsoleLogPage:       return "Console log";
	case CurrentQuickSetPage:         return "QuickSet";
	case CurrentRestartPage:
	case DefaultsRestartPage:
	case SuperAdminRestartPage:       return "Restart map";
	case DefaultsMapsPage:            return "Map cycle";
	case DefaultsRulesPage:           return "Default rules";
	case DefaultsSettingsPage:        return "Game settings";
	case DefaultsBotsPage:            return "Bots";
	case DefaultsIPPolicyPage:        return "IP bans";
	case DefaultsChangePasswordPage:  return "Change password";
	case SuperAdminServerPage:        return "Server settings";
	case SuperAdminWebAdminPage:      return "Web admin users";
	case SuperAdminQuickSetConfigPage:return "QuickSet presets";
	case OPBanList:                   return "OPBan IP policy";
	case DynaList:                    return "Dynamic bans";
	case OPBanOptions:                return "OPBan options";
	case EditUTList:                  return "Edit IP bans as text";
	case EditOPList:                  return "Edit OPBan IP policy";
	case EditDynaList:                return "Edit dynamic bans";
	}
	return "SuperWebAdmin2";
}

function string PrivilegeName(int Priv)
{
	switch (Priv)
	{
	case 1: return "Public moderator";
	case 2: return "Public admin";
	case 3: return "Server moderator";
	case 4: return "Server admin";
	case 5: return "Super admin";
	}
	return "No access";
}

// Map, game, time, players: what an admin checks first, on every page.
function string HUDStrip()
{
	local GameReplicationInfo GRI;
	local string S, Time;
	local Pawn P;
	local int Players, Specs;

	GRI = Level.Game.GameReplicationInfo;
	for (P = Level.PawnList; P != None; P = P.NextPawn)
		if (P.bIsPlayer && !P.bDeleteMe && P.PlayerReplicationInfo != None && SuperServerAdminSpectator(P) == None)
		{
			if (P.PlayerReplicationInfo.bIsSpectator)
				Specs++;
			else
				Players++;
		}

	if (GRI.RemainingTime == 0 && GRI.ElapsedTime != 0)
		Time = Stat(GetStrTime(GRI.ElapsedTime), "elapsed");
	else if (GRI.RemainingTime > 0)
		Time = Stat(GetStrTime(GRI.RemainingTime), "left");
	else
		Time = Stat("-", "not started");

	S = "<section class=\"hud\" aria-label=\"Server status\"><span class=\"map\">"$FixHTML(Left(string(Level), InStr(string(Level), ".")))$"</span>"
		$Stat(GRI.GameName, "game type")
		$Time
		$TeamScore()
		$Stat(Players$" / "$Level.Game.MaxPlayers, "players")
		$Stat(Specs$" / "$Level.Game.MaxSpectators, "spectators")
		$Stat(Eval(Level.ConsoleCommand("get engine.gameinfo GamePassword") != "", "Set", "None"), "game password");
	if (Level.Pauser != "")
		S = S$"<span class=\"stat warn\"><span class=\"v\">Paused</span><span class=\"k\">by "$FixHTML(Level.Pauser)$"</span></span>";
	if (CanUsePage(CurRequest, 2))
		S = S$"<a class=\"restart\" id=\"restart\" href=\"/"$CurrentRestartPage$"\">Restart map</a>";
	return S$"</section>";
}

function string Stat(string Value, string Key)
{
	return "<span class=\"stat\"><span class=\"v\">"$FixHTML(Value)$"</span><span class=\"k\">"$FixHTML(Key)$"</span></span>";
}

// The UT server name (what players see in the server browser).
function string ServerName()
{
	local GameReplicationInfo GRI;

	GRI = Level.Game.GameReplicationInfo;
	if (GRI != None && GRI.ServerName != "")
		return GRI.ServerName;
	return Config.AdminRealm;
}

// "red - blue" score for two-team games, "" otherwise.
function string TeamScore()
{
	local TeamGamePlus TG;

	TG = TeamGamePlus(Level.Game);
	if (TG == None || TG.MaxTeams != 2 || TG.Teams[0] == None || TG.Teams[1] == None)
		return "";
	return Stat(int(TG.Teams[0].Score)$" - "$int(TG.Teams[1].Score), "red - blue");
}

// Confirmation for the Restart button of the info bar. Without JavaScript the button
// is a plain link to the restart page, which asks the same question.
function string RestartDialog()
{
	if (CurRequest == None || !CanUsePage(CurRequest, 2))
		return "";
	return "<dialog id=\"restartdlg\" aria-labelledby=\"restartdlgh\"><form method=\"post\" action=\"/"$CurrentRestartPage$"\">"
		$"<h2 id=\"restartdlgh\">Restart "$FixHTML(Left(string(Level), InStr(string(Level), ".")))$"?</h2>"
		$"<p>Everybody on the server reconnects to the same map, with the current mutators. The current score is lost.</p>"
		$"<div class=\"actions\"><button type=\"button\" id=\"restartno\">Cancel</button>"
		$"<input type=\"submit\" name=\"Restart\" value=\"Restart map\" class=\"danger\"></div></form></dialog>";
}

//-----------------------------------------------------------------------------
// Login page for browsers (SWA2)
//-----------------------------------------------------------------------------

function QueryLogin(SWARequest Request, SWAResponse Response)
{
	local string User, Next, Token;

	Next = Request.GetVariable("Next", "/");
	if (Request.RequestType != Request_POST)
	{
		if (Request.GetVariable("LoggedOut", "") != "")
			ShowLogin(Response, "You are logged out.", false, Next, "");
		else
			ShowLogin(Response, "", false, Next, "");
		return;
	}
	if (Request.IsCrossSite())
	{
		log("SWA: Refused cross-site login from "$Request.ClientIP$".");
		Response.HTTPError(403, "Cross-site requests are not allowed.");
		return;
	}
	User = Request.GetVariable("Username", "");
	if (IsLockedOut(Request.ClientIP))
	{
		ShowLogin(Response, "Too many failed logins from your address. Wait a minute and try again.", true, Next, User);
		return;
	}
	if (!Config.CheckUser(User, Request.GetVariable("Password", "")))
	{
		log("SWA: Failed login from "$Request.ClientIP$", attempt for "$User);
		RecordAuthFailure(Request.ClientIP);
		ShowLogin(Response, "Wrong username or password.", true, Next, User);
		return;
	}
	ClearAuthFailures(Request.ClientIP);
	if (Config.Privileges(User) < 3 && bTournament)
	{
		ShowLogin(Response, "The server is in tournament mode. Your level cannot log in until it is public again.", true, Next, User);
		return;
	}
	Token = Config.NewSession(User, NowMinutes(), Request.ClientIP);
	log("SWA: "$User$"("$Request.ClientIP$") logged in.");
	SendCookieRedirect(Response, SafeNext(Next), "swa2s="$Token$"; Path=/; HttpOnly; SameSite=Strict; Max-Age=604800");
}

// The game server's ip:port. A server bound to every interface reports 0.0.0.0; then the
// host the browser used to reach the web admin is shown, with the game port.
function string ServerAddress()
{
	local string A, H, C;
	local int i;

	A = Level.GetAddressURL();
	if (Left(A, 8) != "0.0.0.0:" || CurRequest == None)
		return A;
	H = CurRequest.HostHeader;
	if (Left(H, 1) == "[")
		i = InStr(H, "]") + 1;   // [IPv6]:port
	else
		i = InStr(H, ":");
	if (i > 0)
		H = Left(H, i);
	if (H == "" || Len(H) > 64)
		return A;
	for (i = 0; i < Len(H); i++)
	{
		C = Mid(H, i, 1);
		if (!((C >= "a" && C <= "z") || (C >= "A" && C <= "Z") || (C >= "0" && C <= "9") || C == "." || C == "-" || C == ":" || C == "[" || C == "]"))
			return A;
	}
	return H $ Mid(A, 7);
}

function ShowLogin(SWAResponse Response, string Message, bool bError, string Next, string User)
{
	Response.Subst("ServerName", FixHTML(ServerName()));
	Response.Subst("Address", FixHTML(ServerAddress()));
	Response.Subst("Next", FixHTML(SafeNext(Next)));
	Response.Subst("Username", FixHTML(Left(User, 32)));
	if (Message == "")
		Response.Subst("Message", "");
	else if (bError)
		Response.Subst("Message", "<p class=\"loginmsg error\" role=\"alert\">"$FixHTML(Message)$"</p>");
	else
		Response.Subst("Message", "<p class=\"loginmsg\" role=\"status\">"$FixHTML(Message)$"</p>");
	Response.IncludeUHTM("login.uhtm");
}

// Where to go after the login: a page of this web admin only ("/page"), never another site.
function string SafeNext(string Next)
{
	if (Left(Next, 1) != "/" || Next == "/" || Next == "/login" || Next == "/logout")
		return "/"$CurrentPlayersPage;
	return "/"$SafePageName(Mid(Next, 1), CurrentPlayersPage);
}

function SendCookieRedirect(SWAResponse Response, string URL, string Cookie)
{
	Response.HTTPResponse("HTTP/1.1 303 See Other");
	Response.HTTPHeader("Server: SuperWebAdmin2");
	Response.HTTPHeader("Location: "$URL);
	Response.HTTPHeader("Set-Cookie: "$Cookie);
	Response.HTTPHeader("Cache-Control: no-cache");
	Response.HTTPHeader("Connection: Close");
	Response.HTTPHeader("");
}

// Minutes since 1970-01-01 on the server clock (for session expiry; survives map changes).
function int NowMinutes()
{
	local int y, m, mp, era, yoe, doy, doe;

	y = Level.Year;
	m = Level.Month;
	if (m <= 2)
		y--;
	era = y / 400;
	yoe = y - era * 400;
	if (m > 2)
		mp = m - 3;
	else
		mp = m + 9;
	doy = (153 * mp + 2) / 5 + Level.Day - 1;
	doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
	return (era * 146097 + doe - 719468) * 1440 + Level.Hour * 60 + Level.Minute;
}

// Shared confirmation dialog (buttons with data-confirm) and the page script
// (Web/swa2.js: theme toggle, mobile menu, dialogs, list widget).
function string PageScript()
{
	return "<dialog id=\"confirmdlg\" aria-labelledby=\"confirmtext\"><h2 id=\"confirmtext\"></h2><div class=\"actions\">"
		$"<button type=\"button\" id=\"confirmno\">Cancel</button><button type=\"button\" id=\"confirmok\" class=\"danger\">OK</button></div></dialog>"
		$"<script src=\"/swa2.js\"></script>";
}

function string BuildNav(string Page)
{
	local string S, G;
	local int Priv;

	Priv = Config.Privileges(CurRequest.Username);

	G = NavLink(CurRequest, 1, 0, CurrentPlayersPage, "Players", Page)
		$NavLink(CurRequest, 1, 0, CurrentConsolePage, "Console", Page)
		$NavLink(CurRequest, 1, 0, CurrentGamePage, "Change map", Page)
		$NavLink(CurRequest, 2, 0, CurrentMutatorsPage, "Mutators", Page)
		$NavLink(CurRequest, 2, 0, CurrentRulesPage, "Rules", Page);
	if (Priv > 2 && GenerateQuickSetOptions() != "")
		G = G$NavLink(CurRequest, 0, 3, CurrentQuickSetPage, "QuickSet", Page);
	S = NavGroup("This map", G);

	G = NavLink(CurRequest, 0, 4, DefaultsMapsPage, "Map cycle", Page)
		$NavLink(CurRequest, 0, 4, DefaultsRulesPage, "Rules", Page)
		$NavLink(CurRequest, 0, 4, DefaultsSettingsPage, "Settings", Page)
		$NavLink(CurRequest, 0, 4, DefaultsBotsPage, "Bots", Page)
		$NavLink(CurRequest, 1, 0, DefaultsIPPolicyPage, "Bans", Page);
	S = S$NavGroup("Defaults", G);

	if (opmain != None)
	{
		G = NavLink(CurRequest, 1, 0, OPBanList, "OPBan policy", Page)
			$NavLink(CurRequest, 1, 0, DynaList, "Dynamic bans", Page)
			$NavLink(CurRequest, 0, 3, EditUTList, "Edit IP bans", Page)
			$NavLink(CurRequest, 0, 3, EditOPList, "Edit OPBan list", Page)
			$NavLink(CurRequest, 0, 3, EditDynaList, "Edit dynamic list", Page);
		S = S$NavGroup("Bans", G);
	}

	if (Priv == 5)
	{
		G = NavLink(CurRequest, 0, 5, SuperAdminServerPage, "Server settings", Page)
			$NavLink(CurRequest, 0, 5, SuperAdminWebAdminPage, "Web admin users", Page)
			$NavLink(CurRequest, 0, 5, SuperAdminQuickSetConfigPage, "QuickSet presets", Page);
		if (opmain != None)
			G = G$NavLink(CurRequest, 0, 5, OPBanOptions, "OPBan options", Page);
		S = S$NavGroup("Administration", G);
	}
	return "<nav class=\"main\" id=\"nav\" aria-label=\"Pages\">"$S$"</nav>";
}

function string NavGroup(string Label, string Links)
{
	if (Links == "")
		return "";
	return "<div class=\"group\"><span>"$Label$"</span>"$Links$"</div>";
}

// MinPublic: lowest level that may use the page outside tournaments (CanUsePage);
// MinLevel: fixed minimum level instead (0 = not used).
function string NavLink(SWARequest Request, int MinPublic, int MinLevel, string Target, string Label, string Page)
{
	if (MinLevel > 0 && Config.Privileges(Request.Username) < MinLevel)
		return "";
	if (MinLevel == 0 && !CanUsePage(Request, MinPublic))
		return "";
	if (Target == Page)
		return "<a class=\"current\" href=\"/"$Target$"\" aria-current=\"page\">"$Label$"</a>";
	return "<a href=\"/"$Target$"\">"$Label$"</a>";
}

//-----------------------------------------------------------------------------
// Old frame pages: redirect, so bookmarks keep working
//-----------------------------------------------------------------------------

function QueryRoot(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentPlayersPage);
}

function QueryMenu(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentPlayersPage);
}

function QueryWelcomePage(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentPlayersPage);
}

function QueryBlankPage(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentPlayersPage);
}

function QueryCurrentMenu(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentPlayersPage);
}

function QueryDefaultsMenu(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$DefaultsMapsPage);
}

function QuerySuperAdminMenu(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$SuperAdminServerPage);
}

function QueryCurrentConsoleSend(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$CurrentConsolePage);
}

function QueryCurrent(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$SafePageName(Request.GetVariable("Page", ""), CurrentPlayersPage));
}

function QuerySuperAdmin(SWARequest Request, SWAResponse Response)
{
	Response.Redirect("/"$SafePageName(Request.GetVariable("Page", ""), SuperAdminServerPage));
}

function QueryDefaults(SWARequest Request, SWAResponse Response)
{
	local string GameType;

	GameType = ValidateGameType(Request.GetVariable("GameType", ""));
	if (GameType != "")
		Response.Redirect("/"$SafePageName(Request.GetVariable("Page", ""), DefaultsMapsPage)$"?GameType="$GameType);
	else
		Response.Redirect("/"$SafePageName(Request.GetVariable("Page", ""), DefaultsMapsPage));
}

// A page name for a redirect: only [a-z0-9_-], so it cannot point anywhere else.
function string SafePageName(string Page, string Fallback)
{
	local int i;
	local string C;

	if (Page == "" || Len(Page) > 40)
		return Fallback;
	for (i = 0; i < Len(Page); i++)
	{
		C = Mid(Page, i, 1);
		if (!((C >= "a" && C <= "z") || (C >= "A" && C <= "Z") || (C >= "0" && C <= "9") || C == "_" || C == "-"))
			return Fallback;
	}
	return Page;
}

// Privilege rule of the form pages: MinPublic is the lowest public level (1 or 2) that
// may use the page outside tournaments; level 3+ may always.
function bool CanUsePage(SWARequest Request, int MinPublic)
{
	local int Priv;

	Priv = Config.Privileges(Request.Username);
	return Priv > 2 || (Priv >= MinPublic && !bTournament);
}

function string Eval(bool bCond, string A, string B)
{
	if (bCond)
		return A;
	return B;
}

// Minutes (0 = none) for DeathMatchPlus games.
function int TimeLimit()
{
	if (DeathMatchPlus(Level.Game) != None)
		return DeathMatchPlus(Level.Game).TimeLimit;
	return 0;
}

//-----------------------------------------------------------------------------
// Brute force protection: MaxAuthFailures failed logins from one IP within
// AuthLockSeconds lock that IP out for AuthLockSeconds.
//-----------------------------------------------------------------------------

function int FindAuthFailSlot(string IP, bool bCreate)
{
	local int i, Oldest;

	for (i = 0; i < ArrayCount(AuthFailIP); i++)
		if (AuthFailIP[i] == IP)
			return i;
	if (!bCreate)
		return -1;
	for (i = 1; i < ArrayCount(AuthFailIP); i++)
		if (AuthFailIP[i] == "" || AuthFailTime[i] < AuthFailTime[Oldest])
			Oldest = i;
	if (AuthFailIP[0] == "")
		Oldest = 0;
	AuthFailIP[Oldest] = IP;
	AuthFailCount[Oldest] = 0;
	AuthFailTime[Oldest] = Level.TimeSeconds;
	return Oldest;
}

function bool IsLockedOut(string IP)
{
	local int i;

	i = FindAuthFailSlot(IP, false);
	if (i == -1 || AuthFailCount[i] < MaxAuthFailures)
		return false;
	if (Level.TimeSeconds - AuthFailTime[i] < AuthLockSeconds)
		return true;
	AuthFailCount[i] = 0;
	return false;
}

function RecordAuthFailure(string IP)
{
	local int i;

	i = FindAuthFailSlot(IP, true);
	if (Level.TimeSeconds - AuthFailTime[i] > AuthLockSeconds)
		AuthFailCount[i] = 0;
	AuthFailCount[i]++;
	AuthFailTime[i] = Level.TimeSeconds;
	if (AuthFailCount[i] == MaxAuthFailures)
		log("SWA: Too many failed logins from "$IP$", locked out for "$AuthLockSeconds$" seconds.");
}

function ClearAuthFailures(string IP)
{
	local int i;

	i = FindAuthFailSlot(IP, false);
	if (i != -1)
	{
		AuthFailIP[i] = "";
		AuthFailCount[i] = 0;
	}
}

// The game password goes into a console command and an HTML attribute. c00lbot uses
// several short passwords joined with ';'.
function bool IsValidGamePassword(string S)
{
	local int i;
	local string C;

	if (Len(S) > 200)
		return false;
	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if (C == " " || C == "\"" || Asc(C) < 32 || Asc(C) == 127)
			return false;
	}
	return true;
}

// Ban reasons are stored in OPBan's dynamic list as IP=days,maps!reason:nick, so the
// separators (and '*', which CheckDynaPolicy treats as a wildcard) must not appear.
function string SanitizeBanText(string S)
{
	S = ReplaceText(S, "*", "^");
	S = ReplaceText(S, "=", "-");
	S = ReplaceText(S, ",", ";");
	S = ReplaceText(S, "!", ".");
	S = ReplaceText(S, ":", ";");
	S = ReplaceText(S, "\"", "'");
	return Left(S, 100);
}

// The GameType parameter of the Defaults pages, or the current game type when it is
// missing or not one of the game types of this server.
function string RequestGameType(SWARequest Request)
{
	local string GameType;

	GameType = ValidateGameType(Request.GetVariable("GameType", ""));
	if (GameType == "")
		GameType = string(Level.Game.Class);
	return GameType;
}

// A value for the colon separated QuickSetConf: no ':' and no control characters.
function string ConfigField(string S)
{
	local int i;
	local string C, Result;

	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if (C != ":" && Asc(C) >= 32)
			Result = Result$C;
	}
	return Result;
}

// IP masks as used by UT/OPBan: digits, dots and the '*' wildcard.
function bool IsValidIPMask(string S)
{
	local int i;
	local string C;

	if (S == "" || Len(S) > 15)
		return false;
	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if (!((C >= "0" && C <= "9") || C == "." || C == "*"))
			return false;
	}
	return true;
}

function bool IsValidPolicy(string AcceptDeny, string IPMask)
{
	return (AcceptDeny ~= "ACCEPT" || AcceptDeny ~= "DENY") && IsValidIPMask(IPMask);
}

// Same rule as for showing the game type controls on the Current Game page.
function bool CanSwitchGameType(SWARequest Request)
{
	local int Priv;

	Priv = Config.Privileges(Request.Username);
	return Priv > 3 || (Priv == 2 && !bTournament);
}

function DisplayMessage(SWAResponse Response, string Title, string Message)
{
	Response.Subst("Title", FixHTML(Title));
	Response.Subst("Message", FixHTML(Message));
	IncludeUHTM(Response, MessageUHTM);
}

static final function string ReplaceText(coerce string Text, coerce string Replace, coerce string With)
{
    local int i;
    local string Output;

    i = InStr(Text, Replace);
    while (i != -1)
	{
        Output = Output$Left(Text, i)$With;
        Text = Mid(Text, i+Len(Replace));
        i = InStr(Text, Replace);
    }
    Output = Output$Text;
    return Output;
}

function string SepRight(string Str)
{
	local int StrLenght;
	local int StrTemp;
	local bool found;

	StrLenght=Len(Str);

	for(StrTemp=1;StrTemp<=StrLenght;StrTemp++)
	{
		if(Right(Left(Str, StrTemp),1)==":")
		{
			found=true;
			break;
		}
	}
	if(found)
		return Right(Str, StrLenght-StrTemp);
	else
		return "";
}

function string SepLeft(string Str)
{
	local int StrLenght;
	local int StrTemp;
	local bool found;

	StrLenght=Len(Str);

	for(StrTemp=1;StrTemp<=StrLenght;StrTemp++)
	{
		if(Right(Left(Str, StrTemp),1)==":")
		{
			found=true;
			break;
		}
	}
	if(found)
		return Left(Str, StrTemp-1);
	else
		return Str;
}

function CheckApps()
{
	local Actor OutActor;
	if(!ActorsChecked)
	{
		ActorsChecked=True;
		foreach Level.Game.AllActors(class'Actor', OutActor, 'IpToCountry')
		{
			bIpToCountry=True;
			IpToCountry=OutActor;
			break;
		}
	}
}

defaultproperties
{
      MenuPage="menu"
      RootPage="root"
      WelcomePage="welcomepage"
      BlankPage="blankpage"
      CurrentPage="current"
      CurrentMenuPage="current_menu"
      CurrentIndexPage="current_index"
      CurrentPlayersPage="current_players"
      CurrentGamePage="current_game"
      CurrentConsolePage="current_console"
      CurrentConsoleLogPage="current_console_log"
      CurrentConsoleSendPage="current_console_send"
      CurrentMutatorsPage="current_mutators"
      CurrentRestartPage="current_restart"
      CurrentRulesPage="current_rules"
      CurrentQuickSetPage="current_quickset"
      DefaultsPage="defaults"
      DefaultsMenuPage="defaults_menu"
      DefaultsMapsPage="defaults_maps"
      DefaultsRulesPage="defaults_rules"
      DefaultsSettingsPage="defaults_settings"
      DefaultsBotsPage="defaults_bots"
      DefaultsIPPolicyPage="defaults_ippolicy"
      DefaultsRestartPage="defaults_restart"
      DefaultsChangePasswordPage="defaults_changepassword"
      SuperAdminPage="superadmin"
      SuperAdminMenuPage="superadmin_menu"
      SuperAdminServerPage="superadmin_server"
      SuperAdminWebAdminPage="superadmin_adminwebadmin1"
      SuperAdminRestartPage="superadmin_restart"
      SuperAdminQuickSetConfigPage="superadmin_quicksetconfig"
      OPBanList="banlist"
      DynaList="DynaList"
      OPBanOptions="ob_options"
      EditOPList="editOPList"
      EditUTList="editUTList"
      EditDynaList="editDynaList"
      MessageUHTM="message.uhtm"
      DefaultClass="normalmenu"
      HighlightedClass="selectedmenu"
}
