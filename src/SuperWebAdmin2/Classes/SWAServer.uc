class SWAServer expands TcpLink;

//var string ServerURL;
var SuperServerAdmin SWA;

var int ConnectionCount;
var SWAConfig Config;


function BeginPlay()
{
	local int i;
	local class<WebApplication> ApplicationClass;
	local IpAddr l;
	local string s;

	Config=new(None) class'SWAConfig';

	Super.BeginPlay();

	SWA = New(None) class'SuperServerAdmin';
	SWA.Config = Config;
	SWA.Level = Level;
	SWA.WebServer = Self;
	SWA.Path = "/";

//	GetLocalIP(l);
//	s = IpAddrToString(l);
//	i = InStr(s, ":");
//	if(i != -1)
//		s = Left(s, i);
//	ServerURL = "http://"$s;

//	if(Config.ListenPort != 80)
//		ServerURL = ServerURL $ ":"$string(Config.ListenPort);

	SWA.ListenPort=BindPort( Config.ListenPort );
	SWA.bListen=Listen();
	SWA.Init();
}

event Destroyed()
{
	SWA.Cleanup();
	SWA.Level = None;
	SWA.WebServer = None;
	SWA = None;
	Super.Destroyed();
}

event GainedChild( Actor C )
{
	Super.GainedChild(C);
	ConnectionCount++;

	// if too many connections, close down listen.
	if(Config.MaxConnections > 0 && ConnectionCount > Config.MaxConnections && LinkState == STATE_Listening)
	{
		Log("SWA: Too many connections, reached limit of "$Config.MaxConnections$" - closing down Listen.");
		Close();
	}
}

event LostChild( Actor C )
{
	Super.LostChild(C);
	ConnectionCount--;

	// if closed due to too many connections, start listening again.
	if(ConnectionCount >= Config.MaxConnections && LinkState != STATE_Listening)
	{
		Log("SWA: Listening again - connections have been closed.");
		Listen();
	}
}

function string FixIpAddr(string IP)
{
	local IpAddr Addr;
	local int i;
	local String StrAddr;

	if(!StringToIpAddr(IP, Addr))
		return "";
	StrAddr=IpAddrToString(Addr);
	i = InStr(StrAddr, ":");
	if(i != -1)
		StrAddr = Left(StrAddr, i);
	else
		return "";
	return StrAddr;
}


defaultproperties
{
      AcceptClass=Class'SuperWebAdmin2.SWAConnection'
}
