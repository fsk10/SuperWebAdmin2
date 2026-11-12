//////////////////////////////////////////////////////////////////////////
//
// Unreal Tournament Ban List Extender
// -----------------------------------
//
// Programmed by PurplePants@purplemetalflake.co.uk
//
// Copyright © PurplePants, 2002-2004
//
// Watcher class (SuperWebAdmin2.OPBanWatcher)
//
//////////////////////////////////////////////////////////////////////////

class OPBanWatcher extends Actor;

var OPBanConfig		opconf;			// Where our config is

var PlayerPawn		Target;			// The player we're watching
var	int				SecsCount;		// How long we've been watching
var int				ID;				// The instance of this watcher
// Saved info in case we lost the player before reporting...
var string          PlayerIP;
var string          PlayerNick;

var int             CheckState;     // Which check we should be doing

// Created and set up, this function kicks off the watching
function Init()
{
	Log(opconf.sApplication$": Watcher "$ID$" starting");
	CheckState = 0;
	SetTimer(1.0, True);	// Do checks every second
}

// Called periodically by the timer, we keep looking to see if the PRI has
// been set up yet and, if so, do the IP checking on the player we're watching
// the kill ourselves.
event Timer()
{
	local int	i, BanIndex;

        // Just check that something hasn't gone wrong...
		SecsCount++;
		if (SecsCount > 15)
			{
			Log(opconf.sApplication$": Watcher "$ID$" aborting after 15 secs without target acquisition");
			ShutDown();
			return;
			}

		// The player to check must still exist...
		if (Target == none)
		   {
		   ShutDown();
		   return;   // ShutDown destroys us; Target was used below anyway
		   }

		if (CheckState == 0)   // Check IP address against perma ban list
		   {
			PlayerIP = Target.GetPlayerNetworkAddress();
			i = InStr(PlayerIP, ":");
			if (i != -1)
			   PlayerIP = Left(PlayerIP, i);

			if (PlayerIP != "")
				{
				PlayerNick = Target.PlayerReplicationInfo.PlayerName;
				Log(opconf.sApplication$": Watcher "$ID$" checking IPPolicy for "$PlayerIP);
				if (!opconf.CheckIPPolicy(PlayerIP))
					{
					opconf.KickPlayer(Target, -1);
					Log(opconf.sApplication $ ": Denied connection for "$PlayerIP);
					ShutDown();
					}
				else
					CheckState = 1;
				}
   			}

		else if (CheckState == 1)    // Check IP against dyna ban list
		     {
		     if (PlayerIP != "")
		        {
				Log(opconf.sApplication$": Watcher "$ID$" checking DynaPolicy for "$PlayerIP);
		        BanIndex = opconf.CheckDynaPolicy(PlayerIP);
		        if (BanIndex != -1)
		           {
		           opconf.KickPlayer(Target, BanIndex);
		           Log(opconf.sApplication $ ": Denied connection for "$PlayerIP);
		           ShutDown();
		           }
                else
                   ShutDown();
		        }
		     }

        else
            CheckState = 0;          // Put things back on track if we get here
}

function ShutDown()
{
	Log(opconf.sApplication$": Shutting down watcher "$ID$" after "$SecsCount$" seconds");
	Destroy();
}

defaultproperties
{
      opconf=None
      Target=None
      SecsCount=0
      Id=0
      PlayerIP=""
      PlayerNick=""
      CheckState=0
}
