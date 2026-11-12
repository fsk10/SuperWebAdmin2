//////////////////////////////////////////////////////////////////////////
//
// Unreal Tournament Ban List Extender
// -----------------------------------
//
// Programmed by PurplePants@purplemetalflake.co.uk
//
// Copyright © PurplePants, 2002-2004
//
// Mutator class (SuperWebAdmin2.OPBanMutator)
//
//////////////////////////////////////////////////////////////////////////

class OPBanMutator extends Mutator;

var OPBanConfig		opconf;		// Where our config is

var int				Watchers;	// Count of watchers spawned (for logging)


// Called by IsRelevant when a player logs in, the PRI is not yet set
// up so network info is not yet available. This is just a trigger to
// spawn our watcher for this player. Note that shitloads of other
// actors also call this function, so we need to single out the ones
// we're interested in and ignore the rest.
function bool CheckReplacement(Actor Other, out byte bSuperRelevant)
{
	local OPBanWatcher opbw;

	if (Other.IsA('PlayerPawn'))	// PlayerPawns are what we want
		{
		if (opconf.bKickPLayers)	// Don't bother if we're not going to kick
			{
			opbw = Level.Spawn(class'OPBanWatcher');	// Create a watcher
			opbw.opconf = opconf;							// Point to our config
			opbw.Target = PlayerPawn(Other);				// Let it know who to watch
			opbw.ID = Watchers++;							// Give it an ID
			opbw.Init();									// Start it running
			}
		}

	return True;
}

defaultproperties
{
      opconf=None
      Watchers=0
}
