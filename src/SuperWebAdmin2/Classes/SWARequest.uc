class SWARequest expands WebRequest;

var string ClientIP;

// Headers used to refuse cross-site requests (CSRF). Basic Auth credentials are sent
// by the browser automatically, so any web page could otherwise post to the webadmin.
var string HostHeader;
var string OriginHeader;
var string RefererHeader;
var string FetchSiteHeader;   // Sec-Fetch-Site (all current browsers, cannot be hidden)
var bool bHasFormData;
// Browser logins (SWA2): the session cookie, and what tells a browser from a script.
var string CookieHeader;
var string AcceptHeader;
var string FetchModeHeader;   // Sec-Fetch-Mode

function ProcessHeaderString(string S)
{
	if (Left(S, 5) ~= "Host:")
		HostHeader = TrimHeader(Mid(S, 5));
	else if (Left(S, 7) ~= "Origin:")
		OriginHeader = TrimHeader(Mid(S, 7));
	else if (Left(S, 8) ~= "Referer:")
		RefererHeader = TrimHeader(Mid(S, 8));
	else if (Left(S, 15) ~= "Sec-Fetch-Site:")
		FetchSiteHeader = TrimHeader(Mid(S, 15));
	else if (Left(S, 15) ~= "Sec-Fetch-Mode:")
		FetchModeHeader = TrimHeader(Mid(S, 15));
	else if (Left(S, 7) ~= "Cookie:")
		CookieHeader = TrimHeader(Mid(S, 7));
	else if (Left(S, 7) ~= "Accept:")
		AcceptHeader = TrimHeader(Mid(S, 7));
	else
		Super.ProcessHeaderString(S);
}

function DecodeFormData(string Data)
{
	if (Data != "")
		bHasFormData = True;
	Super.DecodeFormData(Data);
}

function string TrimHeader(string S)
{
	while (Left(S, 1) == " ")
		S = Mid(S, 1);
	while (Right(S, 1) == " ")
		S = Left(S, Len(S) - 1);
	return S;
}

// host[:port] of an absolute URL
function string HostOfURL(string URL)
{
	local int i;

	i = InStr(URL, "://");
	if (i != -1)
		URL = Mid(URL, i + 3);
	i = InStr(URL, "/");
	if (i != -1)
		URL = Left(URL, i);
	return URL;
}

// True when a browser sent this request from another site. Clients that send none of
// these headers (c00lbot, curl, scripts) are not browsers and are never refused.
function bool IsCrossSite()
{
	if (FetchSiteHeader != "")
		return !(FetchSiteHeader ~= "same-origin" || FetchSiteHeader ~= "none");
	if (OriginHeader != "")
		return OriginHeader ~= "null" || !(HostOfURL(OriginHeader) ~= HostHeader);
	if (RefererHeader != "")
		return !(HostOfURL(RefererHeader) ~= HostHeader);
	return false;
}

// Value of cookie Name, or "".
function string GetCookie(string Name)
{
	local string Rest, Item;
	local int i;

	Rest = CookieHeader;
	while (Rest != "")
	{
		i = InStr(Rest, ";");
		if (i == -1)
		{
			Item = Rest;
			Rest = "";
		}
		else
		{
			Item = Left(Rest, i);
			Rest = Mid(Rest, i + 1);
		}
		Item = TrimHeader(Item);
		if (Left(Item, Len(Name) + 1) == (Name$"="))
			return Mid(Item, Len(Name) + 1);
	}
	return "";
}

// A browser opening a page (gets the login page), as opposed to a script (gets the
// Basic Auth challenge as before).
function bool IsBrowserPage()
{
	return FetchModeHeader ~= "navigate" || InStr(AcceptHeader, "text/html") != -1;
}
