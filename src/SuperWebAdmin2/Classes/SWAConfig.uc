class SWAConfig expands Object config(SWAConfig);

var config int ListenPort;
var config int MaxConnections;
var config bool bOPBanEnabled;
var config string AdminRealm;
var config string UserList[50];
var config string QuickSetConf[20];
var config bool bTickrateInSettings;
var config string Salt;
// Browser logins (SWA2): MD5(Salt$token):user:expiry (minutes, server clock). Only the
// hash of the session token is stored; the token itself lives in the browser's cookie.
var config string Sessions[32];
const SessionMinutes = 10080;   // 7 days
var int SessionCounter;

struct MD5_CTX
{
    var private int status[70];
    var private int count[70];
    var private byte buffer[70];
};

// Usernames end up in the colon separated UserList and in HTML.
static final function bool IsValidUsername(string User)
{
	local int i;
	local string C;

	if (User == "" || Len(User) > 32)
		return false;
	for (i = 0; i < Len(User); i++)
	{
		C = Mid(User, i, 1);
		if (C == ":" || C == "\"" || C == "<" || C == ">" || C == "&" || C == "'" || Asc(C) < 32)
			return false;
	}
	return true;
}

static final function int ClampPrivileges(int Privs)
{
	return Clamp(Privs, 1, 5);
}

// AddUser returns 0 ok, 1 exists, 2 list full, 3 invalid name or password.
function int AddUser(string User, string Pass, int Privs)
{
	local int i;

	if (!IsValidUsername(User) || Pass == "")
		return 3;
	Privs = ClampPrivileges(Privs);
	for (i=0;i<50;i++)
	{
		if(UserList[i] == "")
			break;
		if(SelElem(UserList[i], 1) == User)
			return 1;
	}
    if(i==50)
    	return 2;

	UserList[i] = User$":"$MD5(Salt$Pass)$":"$string(Privs);
	CleanUp();
	SaveConfig();
	return 0;
}

function int DeleteUser(string User)
{
	local int i;

	for(i=0;i<50;i++)
		if (SelElem(Userlist[i],1) == User)
		{
			UserList[i]="";
			EndUserSessions(User);
			SaveConfig();
			CleanUp();
			return 0;
		}
	return 1;
}

function CleanUp()
{
	local int i, j;
 	//just if the field is empty move the next field on its place
	for(i=1;i<50;i++)
	{
		if(UserList[i] != "" && UserList[i-1] == "")
		{
			for(j=0;j<50;j++)
			 	if(UserList[j]=="")
			 		break;
			UserList[j]=UserList[i];
			UserList[i]="";
		}
	}
	SaveConfig();
}

function ChangeUsername(string User, string NewUsername)
{
	local int i;

	for(i=0;i<50;i++)
	{
		if (SelElem(Userlist[i],1) == User)
			UserList[i] = NewUsername$":"$SelElem(UserList[i], 2)$":"$SelElem(UserList[i], 3);
	}
	SaveConfig();
}

function ChangePassword(string User, string NewPassword, optional bool bMD5)
{
	local int i;

	if (User == "" || !UserExists(User))
		return;
	if(bMD5)
		NewPassword=MD5(Salt$NewPassword);

	for(i=0;i<50;i++)
	{
		if (SelElem(Userlist[i], 1) == User)
			UserList[i] = User$":"$NewPassword$":"$SelElem(UserList[i], 3);
	}
	// a new password logs the user out everywhere
	EndUserSessions(User);
	SaveConfig();
}

function ChangePrivileges(string User, int Privs)
{
	local int i;

	if (User == "" || !UserExists(User))
		return;
	Privs = ClampPrivileges(Privs);
	for(i=0;i<50;i++)
	{
		if (SelElem(Userlist[i],1) == User)
			UserList[i] = User$":"$SelElem(UserList[i], 2)$":"$string(Privs);
	}
	SaveConfig();
}

function bool CheckUser(string Username, string Password)
{
	local int i;
	local string temp;

	if(Username == "")
		return false;

	Password=MD5(Salt$Password);

	for(i=0;i<50;i++)
	{
		if(SelElem(Userlist[i], 1) == Username)
		{
			temp=SelElem(Userlist[i], 2);
			// An account without a password is locked, not open (SWA 0.97 let anybody in).
			return temp != "" && temp == Password;
		}
	}
	return false;
}

// Stored passwords are MD5(Salt$Password) as 32 upper case hex digits (DecToHex always
// writes two digits per byte). Anything else in the ini is a plain text password.
// (SWA 0.97 treated everything with 22+ characters as a hash, so long passwords never worked.)
static final function bool IsMD5Hash(string S)
{
	local int i;
	local string C;

	if (Len(S) != 32)
		return false;
	for (i = 0; i < 32; i++)
	{
		C = Mid(S, i, 1);
		if (!((C >= "0" && C <= "9") || (C >= "A" && C <= "F")))
			return false;
	}
	return true;
}


function bool UserExists(string Username)
{
  local int i;

	for(i=0;i<50;i++)
		if(SelElem(Userlist[i], 1) == Username)
			return true;
  return false;
}

function string GetPassword(string Username)
{
  local int i;

	for(i=0;i<50;i++)
		if(SelElem(Userlist[i], 1) == Username)
			return SelElem(Userlist[i], 2);
	return "";
}

function int Privileges(string Username)
{
	local int i;

	for(i=0;i<50;i++)
		if(SelElem(UserList[i], 1)==Username)
			return int(SelElem(Userlist[i], 3));
}

static final function int ElementsNum(string Str, optional string Char)
{
	local int count, pos;

	if(Char=="")
		Char=":";

	while(true)
	{
		pos = InStr(Str, Char);
		if(pos == -1)
			break;
		Str=Mid(Str, pos+1);
		count++;
	}
	return count+1;
}

static final function string SelElem(string Str, int Elem, optional string Char)
{
	local int pos;
	if(Char=="")
		Char=":";

	while(Elem>1)
	{
		pos=InStr(Str, Char);
		if (pos == -1)
			return "";
		Str=Mid(Str, pos+1);
		Elem--;
	}
	pos=InStr(Str, Char);
	if(pos != -1)
    	Str=Left(Str, pos);
    return Str;
}



static final function string SetElem(string Str, int Elem, string SetStr, optional string Char)
{
	local int pos;
	local string LeftSide, RightSide, Temp, OneElem;
	if(Char=="")
		Char=":";

	Temp=Str;

	while(Elem>1)
	{
		pos=InStr(Temp, Char);
		OneElem=Left(Temp, pos+1);
		Temp=Right(Temp, len(Temp)-pos-1);
		Leftside=Leftside$OneElem;
		Elem--;
	}
	pos=InStr(Temp, Char);
	if(pos != -1)
		RightSide=Right(Temp, len(Temp)-pos);
	else // last element, not containing char
		RightSide="";

    return Leftside$SetStr$Rightside;
}

//it's a remake of the code for the UnrealEngine2 from wiki.beyondunreal.com(got from AnthraX)
static final function string MD5 (string str)
{
    local private MD5_CTX context;
    local private byte digest[70];
    local private string Hex;
    local private int i;

    MD5Init (context);
    MD5Update (context, str, Len(str));
    MD5Final (digest, context);

    for (i = 0; i < 16; i++)
        Hex = Hex $ DecToHex(digest[i], 1);

    return Hex;
}

static final function MD5Init(out MD5_CTX context)
{
    context.count[0] = 0;
    context.count[1] = 0;
    context.status[0] = 0x67452301;
    context.status[1] = 0xefcdab89;
    context.status[2] = 0x98badcfe;
    context.status[3] = 0x10325476;
}

static final function MD5Transform(out int Buf[70],byte block[70])
{
    local private int A,B,C,D;
    local private int x[70];

    A = Buf[0];
    B = Buf[1];
    C = Buf[2];
    D = Buf[3];

    Decode (x, block, 64);

    FF (a, b, c, d, x[ 0],  7, 0xd76aa478);
    FF (d, a, b, c, x[ 1], 12, 0xe8c7b756);
    FF (c, d, a, b, x[ 2], 17, 0x242070db);
    FF (b, c, d, a, x[ 3], 22, 0xc1bdceee);
    FF (a, b, c, d, x[ 4],  7, 0xf57c0faf);
    FF (d, a, b, c, x[ 5], 12, 0x4787c62a);
    FF (c, d, a, b, x[ 6], 17, 0xa8304613);
    FF (b, c, d, a, x[ 7], 22, 0xfd469501);
    FF (a, b, c, d, x[ 8],  7, 0x698098d8);
    FF (d, a, b, c, x[ 9], 12, 0x8b44f7af);
    FF (c, d, a, b, x[10], 17, 0xffff5bb1);
    FF (b, c, d, a, x[11], 22, 0x895cd7be);
    FF (a, b, c, d, x[12],  7, 0x6b901122);
    FF (d, a, b, c, x[13], 12, 0xfd987193);
    FF (c, d, a, b, x[14], 17, 0xa679438e);
    FF (b, c, d, a, x[15], 22, 0x49b40821);

    GG (a, b, c, d, x[ 1],  5, 0xf61e2562);
    GG (d, a, b, c, x[ 6],  9, 0xc040b340);
    GG (c, d, a, b, x[11], 14, 0x265e5a51);
    GG (b, c, d, a, x[ 0], 20, 0xe9b6c7aa);
    GG (a, b, c, d, x[ 5],  5, 0xd62f105d);
    GG (d, a, b, c, x[10],  9,  0x2441453);
    GG (c, d, a, b, x[15], 14, 0xd8a1e681);
    GG (b, c, d, a, x[ 4], 20, 0xe7d3fbc8);
    GG (a, b, c, d, x[ 9],  5, 0x21e1cde6);
    GG (d, a, b, c, x[14],  9, 0xc33707d6);
    GG (c, d, a, b, x[ 3], 14, 0xf4d50d87);
    GG (b, c, d, a, x[ 8], 20, 0x455a14ed);
    GG (a, b, c, d, x[13],  5, 0xa9e3e905);
    GG (d, a, b, c, x[ 2],  9, 0xfcefa3f8);
    GG (c, d, a, b, x[ 7], 14, 0x676f02d9);
    GG (b, c, d, a, x[12], 20, 0x8d2a4c8a);

    HH (a, b, c, d, x[ 5],  4, 0xfffa3942);
    HH (d, a, b, c, x[ 8], 11, 0x8771f681);
    HH (c, d, a, b, x[11], 16, 0x6d9d6122);
    HH (b, c, d, a, x[14], 23, 0xfde5380c);
    HH (a, b, c, d, x[ 1],  4, 0xa4beea44);
    HH (d, a, b, c, x[ 4], 11, 0x4bdecfa9);
    HH (c, d, a, b, x[ 7], 16, 0xf6bb4b60);
    HH (b, c, d, a, x[10], 23, 0xbebfbc70);
    HH (a, b, c, d, x[13],  4, 0x289b7ec6);
    HH (d, a, b, c, x[ 0], 11, 0xeaa127fa);
    HH (c, d, a, b, x[ 3], 16, 0xd4ef3085);
    HH (b, c, d, a, x[ 6], 23,  0x4881d05);
    HH (a, b, c, d, x[ 9],  4, 0xd9d4d039);
    HH (d, a, b, c, x[12], 11, 0xe6db99e5);
    HH (c, d, a, b, x[15], 16, 0x1fa27cf8);
    HH (b, c, d, a, x[ 2], 23, 0xc4ac5665);

    II (a, b, c, d, x[ 0],  6, 0xf4292244);
    II (d, a, b, c, x[ 7], 10, 0x432aff97);
    II (c, d, a, b, x[14], 15, 0xab9423a7);
    II (b, c, d, a, x[ 5], 21, 0xfc93a039);
    II (a, b, c, d, x[12],  6, 0x655b59c3);
    II (d, a, b, c, x[ 3], 10, 0x8f0ccc92);
    II (c, d, a, b, x[10], 15, 0xffeff47d);
    II (b, c, d, a, x[ 1], 21, 0x85845dd1);
    II (a, b, c, d, x[ 8],  6, 0x6fa87e4f);
    II (d, a, b, c, x[15], 10, 0xfe2ce6e0);
    II (c, d, a, b, x[ 6], 15, 0xa3014314);
    II (b, c, d, a, x[13], 21, 0x4e0811a1);
    II (a, b, c, d, x[ 4],  6, 0xf7537e82);
    II (d, a, b, c, x[11], 10, 0xbd3af235);
    II (c, d, a, b, x[ 2], 15, 0x2ad7d2bb);
    II (b, c, d, a, x[ 9], 21, 0xeb86d391);

    Buf[0] += A;
    Buf[1] += B;
    Buf[2] += C;
    Buf[3] += D;
}

static final function MD5Update(out MD5_CTX Context,string Data,int inputLen)
{
    local private int i, index, partlen;
    local private byte tmpbuf[70];

    index = ((context.count[0] >>> 3) & 0x3F);
    if ((context.count[0] += (inputLen << 3)) < (inputLen << 3))
        context.count[1]++;
    context.count[1] += (inputLen >>> 29);
    partLen = 64 - index;

    if (inputLen >= partLen)
    {
        MD5Move(Data, 0, context.buffer, index, partLen);
        MD5Transform (context.status, context.buffer);
        for (i = partLen; i + 63 < inputLen; i += 64)
        {
            MD5Move(Data, i, tmpbuf, 0, 64);
            MD5Transform (context.status, tmpbuf);
        }
        index = 0;
    }
    else
        i = 0;

    MD5Move(Data, i, context.buffer, index, inputLen-i);
}

static final function MD5Final (out byte digest[70],out MD5_CTX context)
{
    local private byte bits[70];
    local private int i, index, padLen;
    local private string strbits, PADDING;

    PADDING = chr(0x80);
    for (i = 1; i < 64; i++)
        PADDING = PADDING$chr(0);

    Encode (bits, context.count, 8);

    index = ((context.count[0] >>> 3) & 0x3f);
    if (index < 56)
        padLen = (56 - index);
    else
        padLen = (120 - index);
    MD5Update (context, PADDING, padLen);
    strbits = "";
    for (i=0;i<8;i++)
        strbits = strbits$Chr(bits[i]);
    MD5Update (context, strbits, 8);
    Encode (digest, context.status, 16);

    for (i = 0; i < 64; i++)
    {
        context.buffer[i] = 0;
    }
}

static final function Encode (out byte output [70],int inputt [70],int len)
{
    local int i, j;

    i = 0;
    for (j = 0; j < len; j += 4)
    {
        output[j] = (inputt[i] & 0xff);
        output[j+1] = ((inputt[i] >> 8) & 0xff);
        output[j+2] = ((inputt[i] >> 16) & 0xff);
        output[j+3] = ((inputt[i] >> 24) & 0xff);
        i++;
    }
}


static final function Decode(out int output [70],byte inputt [70],int len)
{
    local int i, j;

    i = 0;
    for (j = 0; j < len; j += 4)
    {
        output[i] = ((inputt[j]) | (int(inputt[j+1]) << 8) | (int(inputt[j+2]) << 16) | (int(inputt[j+3]) << 24));
        i++;
    }
}


static final function MD5Move(string src,int srcindex,out byte buffer[70],int bufindex,int len)
{
    local int i,j;

    j = bufindex;
    for (i = srcindex; i < srcindex+len; i++)
    {
        buffer[j] = Asc(Mid(src, i, 1));
        j++;
        if (j == 64)
            break;
    }
}


static final function int ROTATE_LEFT (int x,int n)
{
    return (((x) << (n)) | ((x) >>> (32-(n))));
}

static final function int F (int x,int y,int z)
{
    return (((x) & (y)) | ((~x) & (z)));
}

static final function int G (int x,int y,int z)
{
    return ((x & z) | (y & (~z)));
}

static final function int H (int x,int y,int z)
{
    return (x ^ y ^ z);
}

static final function int I (int x,int y,int z)
{
    return (y ^ (x | (~z)));
}

static final function FF(out int a,int b,int c,int d,int x,int s,int ac)
{
    a += F(b, c, d) + x + ac;
    a = ROTATE_LEFT (a, s);
    a += b;
}

static final function GG(out int a,int b,int c,int d,int x,int s,int ac)
{
    a += G(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

static final function HH(out int a,int b,int c,int d,int x,int s,int ac)
{
    a += H(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

static final function II(out int a,int b,int c,int d,int x,int s,int ac)
{
    a += I(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

static final function string DecToHex(int dec,int size)
{
    const hex = "0123456789ABCDEF";
    local private string s;
    local int i;

    for (i = 0; i < size*2; i++)
    {
        s = mid(hex, dec & 0xf, 1) $ s;
        dec = dec >>> 4;
    }

    return s;
}

static final function private string randomHash()
{
	return Right("00000"$string(Rand(65536)), 5)$Right("00000"$string(Rand(65536)), 5);
}

//-----------------------------------------------------------------------------
// Browser sessions
//-----------------------------------------------------------------------------

// Starts a session for User and returns the token for the cookie (32 hex digits).
// The token mixes the secret salt with the time, a counter, the client and random
// numbers; only MD5(Salt$token) is stored.
function string NewSession(string User, int Now, string Client)
{
	local int i, Slot, Oldest;
	local string Token;

	SessionCounter++;
	Token = MD5(Salt$":"$User$":"$Now$":"$SessionCounter$":"$Client$":"$FRand()$":"$Rand(2147483647));
	Token = MD5(Token$Salt$FRand()$Rand(2147483647)$GetPassword(User));

	Slot = -1;
	Oldest = 2147483647;
	for (i = 0; i < 32; i++)
	{
		if (Sessions[i] == "" || int(SelElem(Sessions[i], 3)) <= Now)
		{
			Slot = i;
			break;
		}
		if (int(SelElem(Sessions[i], 3)) < Oldest)
		{
			Oldest = int(SelElem(Sessions[i], 3));
			Slot = i;
		}
	}
	Sessions[Slot] = MD5(Salt$Token)$":"$User$":"$string(Now + SessionMinutes);
	SaveConfig();
	return Token;
}

// The user of a valid session, or "".
function string SessionUser(string Token, int Now)
{
	local int i;
	local string H, User;

	if (!IsMD5Hash(Token))
		return "";
	H = MD5(Salt$Token);
	for (i = 0; i < 32; i++)
		if (Sessions[i] != "" && SelElem(Sessions[i], 1) == H)
		{
			User = SelElem(Sessions[i], 2);
			if (int(SelElem(Sessions[i], 3)) > Now && UserExists(User) && GetPassword(User) != "")
				return User;
			return "";
		}
	return "";
}

function EndSession(string Token)
{
	local int i;
	local string H;

	if (!IsMD5Hash(Token))
		return;
	H = MD5(Salt$Token);
	for (i = 0; i < 32; i++)
		if (Sessions[i] != "" && SelElem(Sessions[i], 1) == H)
		{
			Sessions[i] = "";
			SaveConfig();
		}
}

function EndUserSessions(string User)
{
	local int i;

	for (i = 0; i < 32; i++)
		if (Sessions[i] != "" && SelElem(Sessions[i], 2) == User)
			Sessions[i] = "";
}

defaultproperties
{
      ListenPort=5000
      MaxConnections=50
      AdminRealm="UT Server - Webadmin"
      UserList(0)="admin:admin:5"
      QuickSetConf(0)="Public iCTF:BotPack.InstaGibDM:BotPack.CTFGame::0:20:true:true:false:0:N/A:1:100:35:false:12:2"
      QuickSetConf(1)="Normal TDM:BotPack.NoRedeemer:BotPack.TeamGamePlus:true:0:20:false:true:false:100:2:1:100:35:false"
      QuickSetConf(2)="Normal CTF:BotPack.NoRedeemer:BotPack.CTFGame:true:0:20:false:true:true:0:N/A:1:100:35:false"
      QuickSetConf(3)="Instagib CTF:BotPack.InstaGibDM:BotPack.CTFGame:true:0:20:false:true:false:0:N/A:1:100:35:false"
}
