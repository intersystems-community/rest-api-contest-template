Class Anvil.Public Extends %CSP.REST
{
Parameter CHARSET = "utf-8";
Parameter CONTENTTYPE = "application/json";
XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/" Method="GET" Call="Index"/>
<Route Url="/overview" Method="GET" Call="Overview"/>
<Route Url="/ledger" Method="GET" Call="Ledger"/>
<Route Url="/reactor/plan" Method="GET" Call="Plan"/>
</Routes>
}
ClassMethod Index() As %Status { Quit ##class(Anvil.REST).Index() }
ClassMethod Overview() As %Status { Quit ##class(Anvil.REST).Overview() }
ClassMethod Ledger() As %Status { Quit ##class(Anvil.REST).Ledger() }
ClassMethod Plan() As %Status { Quit ##class(Anvil.REST).Plan() }
}
