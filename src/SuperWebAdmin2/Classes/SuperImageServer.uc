class SuperImageServer expands ImageServer;

event Query(WebRequest Request, WebResponse Response)
{
	Super.Query(Request, Response);
}

defaultproperties
{
}
