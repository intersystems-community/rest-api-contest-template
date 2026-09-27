Class Anvil.REST Extends %CSP.REST
{
Parameter CHARSET = "utf-8";
Parameter CONTENTTYPE = "application/json";
Parameter HandleCorsRequest = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/" Method="GET" Call="Index"/>
<Route Url="/overview" Method="GET" Call="Overview"/>
<Route Url="/ledger" Method="GET" Call="Ledger"/>
<Route Url="/reactor/plan" Method="GET" Call="Plan"/>
<Route Url="/proposals" Method="POST" Call="Propose"/>
<Route Url="/proposals/:id/execute" Method="POST" Call="Execute"/>
<Route Url="/proposals/:id/verify" Method="GET" Call="Verify"/>
</Routes>
}

ClassMethod Send(o As %DynamicObject, status As %Integer = 200) As %Status
{
 Set %response.Status=status
 Set %response.ContentType="application/json; charset=utf-8"
 Write o.%ToJSON()
 Quit $$$OK
}

ClassMethod Index() As %Status
{
 Set o=##class(%DynamicObject).%New()
 Set o.name="IRIS Anvil",o.version="0.2.0",o.lifecycle="validate-resolve-plan-execute-verify-receipt"
 Quit ..Send(o)
}

ClassMethod Overview() As %Status
{
 Set o=##class(%DynamicObject).%New()
 Set o.namespace=$Namespace,o.version=$ZVersion,o.time=$ZDateTime($Horolog,3)
 Set o.receipts=$Get(^Anvil.Sequence,0),o.runtime="IRIS",o.cartridge="management"
 Quit ..Send(o)
}

ClassMethod Digest(s As %String) As %String
{
 Quit $System.Encryption.Base64Encode($System.Encryption.SHAHash(256,s))
}

ClassMethod ReactorNodes() As %DynamicArray
{
 Set a=##class(%DynamicArray).%New()
 Set n=##class(%DynamicObject).%New(),n.id="validate",n.label="VALIDATE",n.detail="Validate declared administrative intent",n.depends=##class(%DynamicArray).%New() Do a.%Push(n)
 Set n=##class(%DynamicObject).%New(),n.id="resolve",n.label="RESOLVE",n.detail="Resolve namespace and authority",n.depends=##class(%DynamicArray).%New() Do n.depends.%Push("validate") Do a.%Push(n)
 Set n=##class(%DynamicObject).%New(),n.id="plan",n.label="PLAN",n.detail="Freeze deterministic change set",n.depends=##class(%DynamicArray).%New() Do n.depends.%Push("resolve") Do a.%Push(n)
 Set n=##class(%DynamicObject).%New(),n.id="execute",n.label="EXECUTE",n.detail="Apply allowlisted IRIS operation",n.depends=##class(%DynamicArray).%New() Do n.depends.%Push("plan") Do a.%Push(n)
 Set n=##class(%DynamicObject).%New(),n.id="verify",n.label="VERIFY",n.detail="Re-derive expected state and digest",n.depends=##class(%DynamicArray).%New() Do n.depends.%Push("execute") Do a.%Push(n)
 Set n=##class(%DynamicObject).%New(),n.id="receipt",n.label="RECEIPT",n.detail="Seal execution evidence",n.depends=##class(%DynamicArray).%New() Do n.depends.%Push("verify") Do a.%Push(n)
 Quit a
}

ClassMethod Plan() As %Status
{
 Set o=##class(%DynamicObject).%New()
 Set o.id="deploy-webapp",o.label="Deploy IRIS Web Application",o.lifecycle="maven-reactor"
 Set o.nodes=..ReactorNodes()
 Quit ..Send(o)
}

ClassMethod Propose() As %Status
{
 Set raw=""
 If $IsObject(%request.Content) {
   While '%request.Content.AtEnd { Set raw=raw_%request.Content.Read() }
 }
 If raw="" {
   Set e=##class(%DynamicObject).%New(),e.error="JSON body required"
   Quit ..Send(e,400)
 }
 Set b=##class(%DynamicObject).%FromJSON(raw)
 Set action=b.action,target=b.target,payload=b.payload,key=b.%Get("idempotencyKey","")
 If (action="")!(target="") {
   Set e=##class(%DynamicObject).%New(),e.error="action and target required"
   Quit ..Send(e,400)
 }
 If (key'=""),$Data(^Anvil.Idempotency(key)) {
   Set id=^Anvil.Idempotency(key),row=$Get(^Anvil.Ledger(id))
   Set o=##class(%DynamicObject).%New()
   Set o.id=id,o.state=$List(row,1),o.digest=$List(row,5),o.duplicate=1,o.nodes=..ReactorNodes()
   Quit ..Send(o)
 }
 Set id=$Increment(^Anvil.Sequence)
 Set canonical="iris-anvil/v2|"_action_"|"_target_"|"_payload
 Set digest=..Digest(canonical)
 Set ^Anvil.Ledger(id)=$ListBuild("PLANNED",action,target,payload,digest,$Horolog,"")
 If key'="" Set ^Anvil.Idempotency(key)=id
 Set o=##class(%DynamicObject).%New()
 Set o.id=id,o.state="PLANNED",o.digest=digest,o.nodes=..ReactorNodes()
 Quit ..Send(o,201)
}


ClassMethod AppGet(name As %String, ByRef props) As %Status
{
 New $Namespace Set $Namespace="%SYS"
 Quit ##class(Security.Applications).Get(name,.props)
}

ClassMethod AppCreate(name As %String, ByRef props) As %Status
{
 New $Namespace Set $Namespace="%SYS"
 Quit ##class(Security.Applications).Create(name,.props)
}

ClassMethod AppModify(name As %String, ByRef props) As %Status
{
 New $Namespace Set $Namespace="%SYS"
 Quit ##class(Security.Applications).Modify(name,.props)
}

ClassMethod Execute(id As %Integer) As %Status
{
 Set row=$Get(^Anvil.Ledger(id))
 If row="" {
   Set e=##class(%DynamicObject).%New(),e.error="not found"
   Quit ..Send(e,404)
 }
 If $List(row,1)="EXECUTED" {
   Set o=##class(%DynamicObject).%New()
   Set o.id=id,o.state="EXECUTED",o.receipt=$ListGet(row,7),o.verified=1,o.duplicate=1
   Quit ..Send(o)
 }
 Set action=$List(row,2)
 If action'="DEPLOY_WEB_APP" {
   Set e=##class(%DynamicObject).%New(),e.error="action not allowlisted"
   Quit ..Send(e,403)
 }
 Set target=$List(row,3)
 If target'="/anvil-demo" {
   Set e=##class(%DynamicObject).%New(),e.error="target not allowlisted"
   Quit ..Send(e,403)
 }
 Set desiredNS="USER",desiredDispatch="Anvil.REST"
 Kill before Set beforeSC=..AppGet(target,.before)
 Kill props
 Set props("NameSpace")=desiredNS,props("DispatchClass")=desiredDispatch,props("Enabled")=1
 If $System.Status.IsOK(beforeSC) {
   Set sc=..AppModify(target,.props)
 } Else {
   Set props("AutheEnabled")=64
   Set sc=..AppCreate(target,.props)
 }
 If '$System.Status.IsOK(sc) {
   Set e=##class(%DynamicObject).%New(),e.error=$System.Status.GetErrorText(sc)
   Quit ..Send(e,500)
 }
 Kill after Set afterSC=..AppGet(target,.after)
 If '$System.Status.IsOK(afterSC) {
   Set e=##class(%DynamicObject).%New(),e.error=$System.Status.GetErrorText(afterSC)
   Quit ..Send(e,500)
 }
 Set actual="NameSpace="_$Get(after("NameSpace"))_"|DispatchClass="_$Get(after("DispatchClass"))_"|Enabled="_$Get(after("Enabled"))
 Set verified=($Get(after("NameSpace"))=desiredNS)&($Get(after("DispatchClass"))=desiredDispatch)&($Get(after("Enabled"))=1)
 If 'verified {
   Set e=##class(%DynamicObject).%New(),e.error="postcondition mismatch",e.actual=actual
   Quit ..Send(e,409)
 }
 Set receipt=..Digest("iris-anvil/receipt/v2|"_id_"|"_$List(row,5)_"|"_actual)
 Set $List(row,1)="EXECUTED",$List(row,7)=receipt,^Anvil.Ledger(id)=row
 Set o=##class(%DynamicObject).%New()
 Set o.id=id,o.state="EXECUTED",o.receipt=receipt,o.verified=1,o.actual=actual
 Quit ..Send(o)
}

ClassMethod Verify(id As %Integer) As %Status
{
 Set row=$Get(^Anvil.Ledger(id))
 If row="" {
   Set e=##class(%DynamicObject).%New(),e.error="not found"
   Quit ..Send(e,404)
 }
 Set expected=..Digest("iris-anvil/v2|"_$List(row,2)_"|"_$List(row,3)_"|"_$List(row,4))
 If expected'=$List(row,5) Set expected=..Digest("iris-anvil/v1|"_$List(row,2)_"|"_$List(row,3)_"|"_$List(row,4))
 Set o=##class(%DynamicObject).%New()
 Set verified=(expected=$List(row,5))
 If $List(row,2)="DEPLOY_WEB_APP" {
   Kill actualProps Set appSC=..AppGet($List(row,3),.actualProps)
   Set verified=verified&$System.Status.IsOK(appSC)&($Get(actualProps("NameSpace"))="USER")&($Get(actualProps("DispatchClass"))="Anvil.REST")&($Get(actualProps("Enabled"))=1)
 }
 Set o.id=id,o.state=$List(row,1),o.verified=verified,o.digest=$List(row,5),o.receipt=$ListGet(row,7)
 Quit ..Send(o)
}

ClassMethod Ledger() As %Status
{
 Set a=##class(%DynamicArray).%New()
 Set id=0
 For  Set id=$Order(^Anvil.Ledger(id)) Quit:id=""  Do
 . Set r=^Anvil.Ledger(id)
 . Set x=##class(%DynamicObject).%New()
 . Set x.id=id,x.state=$List(r,1),x.action=$List(r,2),x.target=$List(r,3),x.digest=$List(r,5),x.receipt=$ListGet(r,7)
 . Do a.%Push(x)
 Set o=##class(%DynamicObject).%New(),o.items=a
 Quit ..Send(o)
}
}
