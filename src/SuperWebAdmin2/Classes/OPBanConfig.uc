///////////////////////////////////////////////////////////////////////////
//
// Unreal Tournament Ban List Extender
// -----------------------------------
//
// Programmed by PurplePants@purplemetalflake.co.uk
//
// Copyright © PurplePants, 2002-2004
//
// Configuration class (SuperWebAdmin2.OPBanConfig)
//
// This config actor provides the base for the derived
// actors that use specific config files. Do not use this
// class!
//
//////////////////////////////////////////////////////////////////////////

class OPBanConfig extends Actor;

var string	sApplication, sVersion;

var config string	IPPolicies[250];
var config string   DynaPolicies[250];

var config bool		bCleanPolicy;
var config bool		bKickPlayers;
var config bool		bAnnounceKicks;
var config string	AnnounceTag;

var config int      DefBanMaps;       // Default ban map count
var config int      DefBanDays;       // Default ban day count
var config int      CheckDay;         // Day we last checked what day it is

// Name/pass for automatons
var config string	sAutoName;
var config string	sAutoPass;

// Clean up the UT banlist
function CleanBans()
{
	local int	i, j, IPcnt;
	local int	MaxBans, MaxUTBans;

	MaxBans = ArrayCount(IPPolicies) - 1;
	MaxUTBans = ArrayCount(Level.Game.IPPolicies) - 1;

	Log(sApplication $ ": Cleaning Bans (" $MaxBans$" max)");

	// Start by counting
	for (IPcnt = 0; IPcnt <= MaxUTBans && Level.Game.IPPolicies[IPcnt] != ""; IPcnt++) ;

	// A list with less than 10 slots spare requires cleaning
	if (IPcnt > (MaxUTBans - 10))
		{
		// Nip through the extended list looking for the start of the empties
		for (i = 0; i < MaxBans && IPcnt > (MaxUTBans - 10); i++)
			{
			// Copy all the excess to the extended list....
			if (IPPolicies[i] == "")
				{
				// ...from the start of the UT list
				IPPolicies[i] = Level.Game.IPPolicies[1];
				Log(sApplication $ ": moved policy " $IPPolicies[i]);
				// Move later policies to replace the ones we took out
				for (j = 1; j < MaxUTBans; j++)	// 0 = ACCEPT * - don't remove this!
					{
					Level.Game.IPPolicies[j] = Level.Game.IPPolicies[j + 1];
					}
				Level.Game.IPPolicies[MaxUTBans] = "";
				IPcnt--;
				}
			}
		Level.Game.SaveConfig();
		SaveConfig();
		}
}

// CheckDynaPolicy - given an IP address, run through the dynamic banlist
// to see if there's a match, returning the array index of the ban if found
// or -1 if there is no match
function int CheckDynaPolicy(string Address)
{
    local int  i, marker, MaxBans;

    MaxBans = ArrayCount(DynaPolicies);

    for (i = 0; i < MaxBans; i++)
		{
		// Only the IP part (before '=') may contain the '*' wildcard; the comment after
		// it used to be searched too, which made such bans never match.
		marker = InStr(DynaPolicies[i], "=");
		if (marker > 0)
			marker = InStr(Left(DynaPolicies[i], marker), "*");
		else
			marker = -1;
		if (marker != -1)
			{
			if (Left(Address, marker) == Left(DynaPolicies[i], marker))
				return(i);
			}
		else
			{
			marker = InStr(DynaPolicies[i], "=");
			if (marker > 0)
				{
				if (Address == Left(DynaPolicies[i], marker))
					return(i);
				}
			else
				return(-1);
			}
		}

    return(-1);
}

// CheckIPPolicy - given an IP address, run through the extended banlist
// to see if there's a match, returning aye (==OK) or nay (==ban)
function bool CheckIPPolicy(string Address)
{
	local int i, j, LastMatchingPolicy;
	local string Policy, Mask;
	local bool bAcceptAddress, bAcceptPolicy;
	local int	MaxBans;

	MaxBans = ArrayCount(IPPolicies);

	// strip port number
	j = InStr(Address, ":");
	if (j != -1)
		Address = Left(Address, j);

	bAcceptAddress = True;
	for (i=0; i<MaxBans && IPPolicies[i] != ""; i++)
		{
		j = InStr(IPPolicies[i], ",");
		if (j==-1)
			continue;
		Policy = Left(IPPolicies[i], j);
		Mask = Mid(IPPolicies[i], j+1);
		if (Policy ~= "ACCEPT")
			bAcceptPolicy = True;
		else
			if (Policy ~= "DENY")
			bAcceptPolicy = False;
		else
			continue;

		j = InStr(Mask, "*");
		if (j != -1)
			{
			if (Left(Mask, j) == Left(Address, j))
				{
				bAcceptAddress = bAcceptPolicy;
				LastMatchingPolicy = i;
				}
			}
		else
			{
			if (Mask == Address)
				{
				bAcceptAddress = bAcceptPolicy;
				LastMatchingPolicy = i;
				}
			}
		}

	return (bAcceptAddress);
}

// Deal with updating dynamic ban periods. Called whenever a day or map has
// passed, this function figures out if any dynamic ban has expired and, if
// so, removes 'em from the ban list.
function AdjustDynaPeriods(bool OneDay, bool OneMap)
{
    local int        i, j;
    local int        MaxBans;
    local string     IP;
    local int        Days, Maps;
    local string     comment;

    MaxBans = ArrayCount(DynaPolicies) - 1;

    Log(sApplication $ ": Adjustin Bans ("$(MaxBans - 1)$" max) Days: "$OneDay$", Maps: "$OneMap);

    for (i = 0; i <= MaxBans; i++)
        {
        // Run through the dynamic ban array.
        // Get the data for this ban...
        ExtractDynaData(i, IP, Days, Maps, comment);

        // No IP address means end of list
        if (IP == "")
           break;

        // Deal with a day period...
        if (OneDay)
           {
           if (Days > 0)
              Days--;
           }

        // And/or a map period...
        if (OneMap)
           {
           if (Maps > 0)
              Maps--;
           }

        // No day or map counts means any ban has expired, so...
        if ((Days == 0) && (Maps == 0))
           {
           Log(sApplication$": Removing expired ban - "$IP);

           // Move all hogher bans down over this one
           for (j = i; j < MaxBans; j++)
               DynaPolicies[j] = DynaPolicies[j + 1];

           // Blank out where last ban was
           DynaPolicies[MaxBans] = "";

           // Rerun loop to check the one we just moved down!
           if (i > 0)
              i--;
           }
        else
            SetDynaData(i, IP, Days, Maps, comment); // No ban expired, so update details
        }

    SaveConfig();         // Make sure the system remembers our changes!
}

// Retrieve the ban data associate with some entry in the dynamic ban list.
function ExtractDynaData(int BanIndex, out string IP, out int Days, out int Maps, out string comment)
{
    local int        IPDelim, DaysDelim, MapsDelim;
    local string     BanData;

    IP = "";
    Days = 0;
    Maps = 0;

    if (BanIndex < ArrayCount(DynaPolicies))
        {
        BanData = DynaPolicies[BanIndex];
        IPDelim = InStr(BanData, "=");
        if (IPDelim > 0)
            {
            IP = Left(DynaPolicies[BanIndex], IPDelim);
            DaysDelim = InStr(BanData, ",");
            MapsDelim = InStr(BanData, "!");
            if (DaysDelim > 0)
                {
                Days = int(Mid(BanData, IPDelim + 1, DaysDelim - IPDelim - 1));
                if (MapsDelim > 0)
                    {
                    Maps = int(Mid(BanData, DaysDelim + 1, MapsDelim - DaysDelim - 1));
                    comment = Mid(BanData, MapsDelim + 1);
                    }
                else
                    {
                    Maps = int(Mid(BanData, DaysDelim + 1));
                    comment = "";
                    }
                }
            }
        }
}

// Set the ban data associated with a particular item in the dynamic ban list
function SetDynaData(int BanIndex, string IP, int Days, int Maps, string comment)
{
    if (BanIndex < ArrayCount(DynaPolicies))
        {
        if (comment == "")
            DynaPolicies[BanIndex] = IP$"="$Days$","$Maps;
        else
            DynaPolicies[BanIndex] = IP$"="$Days$","$Maps$"!"$comment;
        SaveConfig();
        }
}

// Add a dynamic ban
function int AddDynaBan(string IP, int BanDays, int BanMaps, string comment)
{
    local int        i, MaxBans;
    local string     sTemp;

    for (i = 0; i < ArrayCount(DynaPolicies); i++)
        {
        if (DynaPolicies[i] == "")
            {
            SetDynaData(i, IP, BanDays, BanMaps, comment);
            sTemp = "Added ban - "$IP$" Days/Maps = "$BanDays$"/"$BanMaps$" "$comment;
            SaveConfig();         // Make sure the system remembers our changes!
            log(sApplication$": "$sTemp);
            return(i);
            }
        }
    sTemp = "Unable to add new ban ("$IP$") - list full";
    log(sApplication$": "$sTemp);
    return(-1);
}

function int AddIPPolicy(string IP, bool bDeny)
{
    local int        i, MaxBans;
    local string     sTemp, sPolicy;

    if (bDeny)
       sPolicy = "DENY";
    else
       sPolicy = "ACCEPT";

    for (i = 0; i < ArrayCount(IPPolicies); i++)
        {
        if (IPPolicies[i] == "")
            {
            IPPolicies[i] = sPolicy$","$IP;
            sTemp = "Added policy - "$sPolicy$","$IP;
            SaveConfig();         // Make sure the system remembers our changes!
            log(sApplication$": "$sTemp);
            return(i);
            }
        }
    sTemp = "Unable to add new policy ("$sPolicy$","$IP$") - list full";
    log(sApplication$": "$sTemp);
    return(-1);

}

function KickPlayer(PlayerPawn Target, int BanIndex)
{
    local string        BanIP, PlayerIP, PlayerNick;
    local int           BanDays, BanMaps;
    local string        sTemp, comment;

    PlayerNick = Target.PlayerReplicationInfo.PlayerName;
    PlayerIP = Target.GetPlayerNetworkAddress();
    PlayerIP = Left(PlayerIP, InStr(PlayerIP,":"));

    if (BanIndex != -1)
        {
        ExtractDynaData(BanIndex, BanIP, BanDays, BanMaps, comment);
        sTemp = "kicked "$PlayerIP$" ("$PlayerNick$") - banned (days/maps = "$BanDays$"/"$BanMaps$")";
        }
    else
        sTemp = "kicked "$PlayerIP$" ("$PlayerNick$")";
    Target.ClientMessage("You are currently banned on this server.");
    log(sApplication$": "$sTemp$" "$comment);
    if (bAnnounceKicks)
       BroadcastMessage(AnnounceTag$": "$sTemp);
    Target.Destroy();
}

defaultproperties
{
      sApplication=""
      sVersion=""
      bCleanPolicy=True
      bKickPlayers=True
      bAnnounceKicks=True
      AnnounceTag="OPBan"
      DefBanMaps=0
      DefBanDays=5
      CheckDay=0
      sAutoName=""
      sAutoPass=""
}
