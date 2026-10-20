#!/usr/bin/env python3
"""One stdio MCP connection; resolve local project metadata and use the signed broker CLI."""
import concurrent.futures, importlib.util, json, os, pathlib, re, subprocess, sys, tempfile, threading

ENVIRONMENTS={'dev','staging','prod'}
VARIABLE=re.compile(r'[A-Za-z_][A-Za-z0-9_]{0,127}')
BINDING_KINDS={'value','apiKey','keyValue','json','text','file'}
PROVIDERS={'OpenAI','Anthropic','Gemini','GitHub','Cloudflare','Paddle','RevenueCat','Stripe','Resend','Vercel','Sentry'}
MAX_INPUT=300000

def valid_pointer(pointer):
    return isinstance(pointer,str) and (pointer=='' or pointer.startswith('/')) and len(pointer.encode('utf-8'))<=2048 and pointer.count('/')<=64 and '\0' not in pointer and re.search(r'~(?![01])',pointer) is None

def read_metadata(path):
    if not path.exists():return None
    if path.is_symlink() or path.stat().st_size>65536:raise ValueError('Invalid metadata file')
    return json.loads(path.read_text())

def binding_map(value):
    if not isinstance(value,dict):raise ValueError('Invalid bindings')
    return {n:k for n,k in value.items() if isinstance(n,str) and VARIABLE.fullmatch(n) and k in BINDING_KINDS}

def resolve(repository, project=None, home=None):
    home=home or pathlib.Path.home()
    if not isinstance(repository,str) or not pathlib.Path(repository).is_absolute():raise ValueError('Absolute repository directory required')
    directory=pathlib.Path(repository).resolve()
    if not directory.is_dir():raise ValueError('Repository directory not found')
    if project is not None and (not isinstance(project,str) or not project or len(project)>128):raise ValueError('Invalid project')
    for root in [directory,*directory.parents]:
        config=read_metadata(root/'keydesk.project.json')
        if config is not None:
            if not isinstance(config,dict) or config.get('version')!=1 or not isinstance(config.get('project'),str) or not config['project'] or len(config['project'])>100:raise ValueError('Invalid project manifest')
            if project and project!=config['project']:raise ValueError('Project conflicts with repository manifest')
            bindings=config.get('bindings',{})
            if not isinstance(bindings,dict) or not set(bindings).issubset(ENVIRONMENTS):raise ValueError('Invalid manifest environments')
            return {'state':'resolved','source':'repository_manifest','repository':str(root),'project':config['project'],'bindings':{env:binding_map(items) for env,items in bindings.items()}}
    registry=read_metadata(home/'.config/keydesk/mcp-connections.json') or []
    receipts=read_metadata(home/'.config/keydesk/imported-files.json') or []
    if not isinstance(registry,list) or not isinstance(receipts,list):raise ValueError('Invalid local registry')
    # Exact names only. No provider-wide production fallback or fuzzy repository match.
    target=project or directory.name;bindings={};sources=[]
    for row in registry:
        if isinstance(row,dict) and row.get('project')==target and row.get('environment') in ENVIRONMENTS:
            bindings.setdefault(row['environment'],{}).update(binding_map(row.get('knownBindings',{})));sources.append('local_connection_registry')
    for row in receipts:
        if not isinstance(row,dict) or row.get('project')!=target:continue
        env=row.get('environment');name=row.get('variable');kind=row.get('kind')
        if env in ENVIRONMENTS and isinstance(name,str) and VARIABLE.fullmatch(name) and kind in BINDING_KINDS:
            bindings.setdefault(env,{})[name]=kind;sources.append('local_import_receipt')
    if bindings:return {'state':'resolved','source':sorted(set(sources)),'repository':str(directory),'project':target,'bindings':bindings,'inventory':'metadata only; may be stale'}
    return {'state':'unconfigured','repository':str(directory),'required':'Establish this repository\'s Keydesk project and variable names; add a names-only keydesk.project.json. Never infer prod from provider availability.'}

def validate_request(arguments,home=None):
    allowed={'repository','project','environment','key','field','provider','method','url','body'}
    if not isinstance(arguments,dict) or not set(arguments).issubset(allowed):raise ValueError('Unsupported arguments')
    context=resolve(arguments.get('repository'),arguments.get('project'),home)
    if context['state']!='resolved':raise ValueError('Project context missing')
    env=arguments.get('environment');key=arguments.get('key')
    if not isinstance(env,str) or env not in ENVIRONMENTS or not isinstance(key,str) or not VARIABLE.fullmatch(key):raise ValueError('Select an existing binding in this environment')
    kind=context['bindings'].get(env,{}).get(key)
    if 'field' in arguments:
        if kind not in {'value','keyValue','json'} or not valid_pointer(arguments['field']):raise ValueError('Select a configured key-value/JSON field')
    elif kind not in {'value','apiKey'}:raise ValueError('Select an existing API-key binding')
    if 'provider' in arguments and ('field' not in arguments or not isinstance(arguments['provider'],str) or arguments['provider'] not in PROVIDERS):raise ValueError('Invalid field provider')
    if arguments.get('method') not in {'GET','HEAD','POST','PUT','PATCH','DELETE'} or not isinstance(arguments.get('url'),str):raise ValueError('Invalid request')
    body=arguments.get('body')
    if body is not None:
        if not isinstance(body,str) or len(body.encode())>262144 or '\0' in body:raise ValueError('Invalid JSON body')
        json.loads(body)
    return context

def execute(arguments,runner=None,home=None):
    context=validate_request(arguments,home);home=home or pathlib.Path.home();cli=home/'.local/bin/keydesk'
    if not cli.is_file():raise ValueError('Signed Keydesk CLI missing')
    argv=[str(cli),'request','--project',context['project'],'--env',arguments['environment'],'--key',arguments['key'],'--method',arguments['method'],'--url',arguments['url']]
    if 'field' in arguments:argv+=['--field',arguments['field']]
    if 'provider' in arguments:argv+=['--provider',arguments['provider']]
    with tempfile.TemporaryDirectory(prefix='keydesk-mcp-body-') as directory:
        if arguments.get('body') is not None:
            path=pathlib.Path(directory)/'body.json'
            fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'w') as output:output.write(arguments['body'])
            argv+=['--body-file',str(path)]
        result=(runner or subprocess.run)(argv,capture_output=True,text=True,timeout=150)
        if result.returncode not in (0,2):return {'error':'keydesk_request_not_completed','retry':'Do not automatically retry; user readiness required. External outcome may be unknown.'}
        payload=json.loads(result.stdout)
        if not isinstance(payload,dict) or not isinstance(payload.get('status'),int):raise ValueError('Invalid broker result')
        return payload

def schema(properties,required):return {'type':'object','properties':properties,'required':required,'additionalProperties':False}
STRING={'type':'string'}
TOOLS=[
 {'name':'project_context','description':'Find this session repository\'s Keydesk project and variable names from names-only local metadata. Supply the actual absolute repository path; do not use the MCP process cwd. No vault values or live vault listing. An unconfigured result needs a repository mapping, never a per-project MCP installation.','inputSchema':schema({'repository':STRING,'project':STRING},['repository'])},
 {'name':'request_http','description':'Call a supported official API using a configured API key or a string field selected by RFC 6901 pointer from a key-value/JSON document. Supply field only when its path is already established; no leaf listing or credential reads. Other-classified documents require provider; a classified document must match it. Signed Cellar enforces provider hosts and approval. Returns provider data, never the selected credential. File/SDK execution uses keydesk run.','inputSchema':schema({'repository':STRING,'project':STRING,'environment':{'type':'string','enum':sorted(ENVIRONMENTS)},'key':STRING,'field':{'type':'string','maxLength':2048,'description':'RFC 6901 JSON Pointer; empty string selects a scalar root. Use known field names only.'},'provider':{'type':'string','enum':sorted(PROVIDERS)},'method':{'type':'string','enum':['GET','HEAD','POST','PUT','PATCH','DELETE']},'url':STRING,'body':{'type':'string','maxLength':262144}},['repository','environment','key','method','url'])}
]

def serve():
    output_lock=threading.Lock();ready=False;initialized=False;pool=concurrent.futures.ThreadPoolExecutor(max_workers=4);pending={};pending_lock=threading.Lock();processes={}
    def send(message):
        with output_lock:print(json.dumps(message,ensure_ascii=False),flush=True)
    def tool_result(identifier,payload):
        send({'jsonrpc':'2.0','id':identifier,'result':{'content':[{'type':'text','text':json.dumps(payload,ensure_ascii=False)}],'structuredContent':payload,'isError':'error' in payload}})
    def request(identifier,args):
        def run_signed(argv,**kwargs):
            with pending_lock:
                if pending.get(str(identifier))=='cancelled':raise ValueError('Cancelled')
                process=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                processes[str(identifier)]=process
            try:
                stdout,stderr=process.communicate(timeout=kwargs['timeout'])
                return subprocess.CompletedProcess(argv,process.returncode,stdout,stderr)
            except subprocess.TimeoutExpired:
                process.kill();process.communicate();raise
            finally:
                with pending_lock:processes.pop(str(identifier),None)
        try:payload=execute(args,runner=run_signed)
        except (ValueError,OSError,subprocess.SubprocessError):payload={'error':'invalid_context_or_broker_unavailable','retry':'No automatic retry. Confirm repository mapping and vault readiness.'}
        with pending_lock:
            cancelled=pending.pop(str(identifier),None)=='cancelled'
        if not cancelled:tool_result(identifier,payload)
    try:
        while True:
            line=sys.stdin.buffer.readline(MAX_INPUT+1)
            if not line:break
            if len(line)>MAX_INPUT:raise ValueError('Oversized MCP input')
            try:
                msg=json.loads(line);identifier=msg.get('id');method=msg.get('method')
                if msg.get('jsonrpc')!='2.0':raise ValueError('Invalid JSON-RPC')
                if method=='notifications/initialized':ready=initialized;continue
                if method=='notifications/cancelled':
                    with pending_lock:
                        target=str(msg.get('params',{}).get('requestId'))
                        if target in pending:
                            pending[target]='cancelled'
                            process=processes.get(target)
                            if process is not None and process.poll() is None:process.terminate()
                    continue
                if identifier is None:continue
                if not isinstance(identifier,(int,str)) or isinstance(identifier,bool):raise ValueError('Invalid ID')
                if method=='initialize' and not initialized:
                    initialized=True
                    send({'jsonrpc':'2.0','id':identifier,'result':{'protocolVersion':'2025-11-25','capabilities':{'tools':{}},'serverInfo':{'name':'keydesk','version':'0.7.20-project-router-2'},'instructions':'One connection serves multiple projects. Resolve project_context using the actual session repository path, then call request_http with that repository, environment and key name. A known key-value/JSON string field can be selected using field and provider. Missing mappings need clarification; do not borrow another project\'s key or enumerate document contents. Keydesk human approval remains required.'}})
                elif method=='ping':send({'jsonrpc':'2.0','id':identifier,'result':{}})
                elif method=='tools/list' and ready:send({'jsonrpc':'2.0','id':identifier,'result':{'tools':TOOLS}})
                elif method=='tools/call' and ready:
                    params=msg.get('params',{});name=params.get('name');args=params.get('arguments',{})
                    if name=='project_context':
                        if not isinstance(args,dict) or not set(args).issubset({'repository','project'}):raise ValueError('Invalid context arguments')
                        tool_result(identifier,resolve(args.get('repository'),args.get('project')))
                    elif name=='request_http':
                        with pending_lock:
                            if len(pending)>=4 or str(identifier) in pending:raise ValueError('Busy or duplicate request')
                            pending[str(identifier)]='pending'
                        pool.submit(request,identifier,args)
                    else:raise ValueError('Unsupported tool')
                else:send({'jsonrpc':'2.0','id':identifier,'error':{'code':-32601,'message':'Unsupported method or not initialized'}})
            except (ValueError,TypeError,AttributeError,OSError):send({'jsonrpc':'2.0','id':locals().get('identifier'),'error':{'code':-32602,'message':'Invalid parameters or project metadata; values withheld'}})
    finally:
        # No retry on disconnect. Requests already submitted can have external effects.
        with pending_lock:
            for target in pending:pending[target]='cancelled'
            for process in processes.values():
                if process.poll() is None:process.terminate()
        pool.shutdown(wait=True,cancel_futures=True)

if __name__=='__main__':
    if len(sys.argv)!=1:raise SystemExit('stdio MCP adapter takes no project or environment arguments')
    serve()
