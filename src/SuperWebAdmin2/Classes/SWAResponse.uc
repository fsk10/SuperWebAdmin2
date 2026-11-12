class SWAResponse expands WebResponse;

var SWAConnection Connection;
var bool bSentText; // used to warn headers already sent
var bool bSentResponse;
var WebRequest Request;

event SendText(string Text, optional bool bNoCRLF)
{
	if(!bSentText)
	{
		SendStandardHeaders();
		bSentText = True;
	}

	if(bNoCRLF)
		Connection.SendText(Text);
	else
		Connection.SendText(Text$Chr(13)$Chr(10));
}

event SendBinary(int Count, byte B[255])
{
	Connection.SendBinary(Count, B);
}

function HTTPHeader(string Header)
{
//	if(bSentText)
//		Log("Can't send headers - already called SendText()");

	Connection.SendText(Header$Chr(13)$Chr(10));
}

function SendStandardHeaders( optional string ContentType, optional bool bCache )
{
	if(ContentType == "")
		ContentType = "text/html";
	if(!bSentResponse)
		HTTPResponse("HTTP/1.1 200 OK");
	HTTPHeader("Server: SuperWebAdmin2");
	HTTPHeader("Content-Type: "$ContentType);
	if(ContentType=="text/html" || ContentType=="text/css" || ContentType=="text/javascript")
		HTTPHeader("Cache-Control: no-cache");
	HTTPHeader("Connection: Close"); /* server does not support KeepAlive */
	HTTPHeader("");
	bSentText = True;
}

function FailAuthentication(string Realm)
{
        HTTPError(401, Realm);
}

function HTTPError(int ErrorNum, optional string Data)
{
        switch(ErrorNum)
        {
        case 400:
                HTTPResponse("HTTP/1.1 400 Bad Request");
                SendText("<title>400 Bad Request</title><h1>400 Bad Request</h1>");
                break;
        case 403:
                HTTPResponse("HTTP/1.1 403 Forbidden");
                SendText("<title>403 Forbidden</title><h1>403 Forbidden</h1>"$Data);
                break;
        case 401:
                HTTPResponse("HTTP/1.1 401 Unauthorized");
                HTTPHeader("WWW-authenticate: basic realm=\""$Data$"\"");
                SendText("<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"iso-8859-1\"><title>Log in</title>"
                        $"<link rel=\"stylesheet\" href=\"/swa2.css\">"
                        $"<script>try{if(localStorage.getItem('swa2-theme')=='light')document.documentElement.setAttribute('data-theme','light');}catch(e){}</script>"
                        $"</head><body class=\"loggedout\"><div class=\"block\">"
                        $"<h1>Not logged in</h1><p>You are logged out, or the login was not accepted.</p>"
                        $"<p><a href=\"/login\">Log in</a></p></div></body></html>");
                break;
        case 404:
                HTTPResponse("HTTP/1.1 404 Object Not Found");
                SendText("<title>404 Not Found</title><h1>404 Not Found</h1>The URL you requested was not found.");
                break;
        default:
                break;
        }
}

function HTTPResponse(string Header)
{
        HTTPHeader(Header);
        bSentResponse = True;
}

defaultproperties
{
}
