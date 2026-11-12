//////////////////////////////////////////////////////////////////////////
//
// Unreal Tournament Ban List Extender
// -----------------------------------
//
// Programmed by PurplePants@purplemetalflake.co.uk
//
// Copyright © PurplePants, 2002-2004
//
//////////////////////////////////////////////////////////////////////////

class OPBan extends Actor config (system);

var bool			bInitialised;
var string			sApplication;
var string			sVersion;
var OPBanConfig		opconf;
//var OPBanWeb		opwebapp;
var OPBanMutator	opmutator;

var config bool		bUseSystemIni;
var config bool		bLockIniChoice;

event PreBeginPlay()
{
	// Only handle this event the first time
	if (bInitialised)
		return;
	bInitialised = TRUE;

	Log(sApplication $ ": OP's ban list extender " $ sVersion $ " loading...");

	// Load up configuration using the desired .ini
	if (bUseSystemIni)
		opconf = Spawn(class'SuperWebAdmin2.OPBanConfigUT');
	else
		opconf = Spawn(class'SuperWebAdmin2.OPBanConfigOP');
	// Add the app details to the configuration
	opconf.sApplication = sApplication;
	opconf.sVersion = sVersion;

	// Fix policy 0 which we can't do automagically...
	if (opconf.IPPolicies[0] == "")
		{
		opconf.IPPolicies[0] = "ACCEPT,*";
		opconf.SaveConfig();
		}
}

function PostBeginPlay()
{
	local OPBanMutator opbm;

	Super.PostBeginPLay();

	// Check we're not already loaded
	foreach AllActors(class 'OPBanMutator', opbm)
		return;

	// Clean the UT ban list
	if (opconf.bCleanPolicy)
		opconf.CleanBans();

	// Create our mutator and point it at the configuration class
	opMutator = Level.Spawn(Class'OPBanMutator');
	opMutator.opconf = opconf;
	// Insert our mutator in the master list
	opMutator.NextMutator = Level.Game.BaseMutator;
	Level.Game.BaseMutator = opMutator;

	if (opconf.CheckDay != Level.Day)
    	{
		opconf.CheckDay = Level.Day;
		opconf.AdjustDynaPeriods(True, True);
		}
	else
		opconf.AdjustDynaPeriods(False, True);
}

defaultproperties
{
      bInitialised=False
      sApplication="OPBan"
      sVersion="V0.7"
      opconf=None
      opmutator=None
      bUseSystemIni=False
      bLockIniChoice=False
}
