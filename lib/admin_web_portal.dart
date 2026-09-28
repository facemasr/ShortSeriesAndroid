part of 'main.dart';

class AdminWebHubPage extends StatelessWidget {
  final String userEmail;
  const AdminWebHubPage({super.key,this.userEmail=''});

  void _open(BuildContext context,String path,String title){
    AppNavigator.open(
      context,
      AdminWebPanelPage(
        initialPath:path,
        title:title,
        userEmail:userEmail,
      ),
      key:'admin/web/${Uri.encodeComponent(path)}',
    );
  }

  @override
  Widget build(BuildContext context){
    final ar=Api.I.ar;
    final sections=<({String path,String ar,String en,IconData icon})>[
      (path:'/admin',ar:'الرئيسية',en:'Dashboard',icon:Icons.dashboard_rounded),
      (path:'/admin/users',ar:'المشتركون',en:'Users',icon:Icons.group_rounded),
      (path:'/admin/media',ar:'المحتوى',en:'Content',icon:Icons.video_library_rounded),
      (path:'/admin/people',ar:'الفنانون',en:'Artists',icon:Icons.people_alt_outlined),
      (path:'/admin/channels',ar:'القنوات',en:'TV Channels',icon:Icons.live_tv_rounded),
      (path:'/admin/home-builder',ar:'الصفحة الرئيسية',en:'Home Builder',icon:Icons.view_quilt_rounded),
      (path:'/admin/sliders',ar:'السلايدر',en:'Sliders',icon:Icons.view_carousel_rounded),
      (path:'/admin/menus',ar:'القوائم',en:'Menus',icon:Icons.menu_open_rounded),
      (path:'/admin/pages',ar:'الصفحات',en:'Pages',icon:Icons.article_outlined),
      (path:'/admin/ads',ar:'الإعلانات',en:'Ads',icon:Icons.campaign_outlined),
      (path:'/admin/comments',ar:'التعليقات',en:'Comments',icon:Icons.comment_outlined),
      (path:'/admin/reports',ar:'البلاغات',en:'Reports',icon:Icons.report_outlined),
      (path:'/admin/analytics',ar:'التحليلات',en:'Analytics',icon:Icons.query_stats_rounded),
      (path:'/admin/settings',ar:'الإعدادات',en:'Settings',icon:Icons.settings_rounded),
      (path:'/admin/plugins',ar:'الإضافات',en:'Plugins',icon:Icons.extension_rounded),
      (path:'/admin/plugin-importers',ar:'أدوات الجلب',en:'Importers',icon:Icons.cloud_download_outlined),
      (path:'/admin/redirects',ar:'إعادة التوجيه',en:'Redirects',icon:Icons.alt_route_rounded),
      (path:'/admin/audit',ar:'سجل العمليات',en:'Audit Log',icon:Icons.manage_history_rounded),
      (path:'/admin/backup',ar:'النسخ الاحتياطي',en:'Backup',icon:Icons.backup_outlined),
      (path:'/admin/system',ar:'حالة النظام',en:'System',icon:Icons.memory_rounded),
    ];

    return Scaffold(
      appBar:AppBar(
        title:Text(ar?'لوحة تحكم الموقع':'Website Admin'),
      ),
      body:ListView(
        padding:const EdgeInsets.fromLTRB(14,14,14,28),
        children:[
          Card(
            clipBehavior:Clip.antiAlias,
            child:InkWell(
              onTap:()=>_open(context,'/admin',ar?'لوحة التحكم':'Admin Dashboard'),
              child:Padding(
                padding:const EdgeInsets.all(18),
                child:Row(
                  children:[
                    Container(
                      width:62,height:62,
                      decoration:BoxDecoration(
                        color:const Color(0x22E50914),
                        borderRadius:BorderRadius.circular(18),
                      ),
                      child:const Icon(Icons.admin_panel_settings_rounded,size:34,color:Color(0xFFE50914)),
                    ),
                    const SizedBox(width:14),
                    Expanded(
                      child:Column(
                        crossAxisAlignment:CrossAxisAlignment.start,
                        children:[
                          Text(
                            ar?'لوحة التحكم الكاملة':'Full Website Control Panel',
                            style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900),
                          ),
                          const SizedBox(height:4),
                          Text(
                            ar
                              ?'نفس لوحة إدارة الموقع على الويب داخل التطبيق.'
                              :'The complete website admin panel inside the app.',
                            style:const TextStyle(color:Colors.white60,height:1.4),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height:16),
          Text(
            ar?'أقسام الإدارة':'Administration',
            style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900),
          ),
          const SizedBox(height:10),
          GridView.builder(
            shrinkWrap:true,
            physics:const NeverScrollableScrollPhysics(),
            itemCount:sections.length,
            gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:190,
              childAspectRatio:1.35,
              crossAxisSpacing:10,
              mainAxisSpacing:10,
            ),
            itemBuilder:(_,i){
              final item=sections[i];
              return Card(
                clipBehavior:Clip.antiAlias,
                child:InkWell(
                  onTap:()=>_open(context,item.path,ar?item.ar:item.en),
                  child:Padding(
                    padding:const EdgeInsets.all(13),
                    child:Column(
                      mainAxisAlignment:MainAxisAlignment.center,
                      children:[
                        Icon(item.icon,size:30),
                        const SizedBox(height:8),
                        Text(
                          ar?item.ar:item.en,
                          textAlign:TextAlign.center,
                          maxLines:2,
                          overflow:TextOverflow.ellipsis,
                          style:const TextStyle(fontWeight:FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AdminWebPanelPage extends StatefulWidget {
  final String initialPath;
  final String title;
  final String userEmail;

  const AdminWebPanelPage({
    super.key,
    this.initialPath='/admin',
    required this.title,
    this.userEmail='',
  });

  @override
  State<AdminWebPanelPage> createState()=>_AdminWebPanelPageState();
}

class _AdminWebPanelPageState extends State<AdminWebPanelPage>{
  late final WebViewController controller;
  int progress=0;
  bool loginPage=false;
  String currentUrl='';

  Uri _uri(String path){
    if(path.startsWith('http://')||path.startsWith('https://')){
      return Uri.parse(path);
    }
    return Uri.parse('https://shortseris.online${path.startsWith('/')?path:'/$path'}');
  }

  @override
  void initState(){
    super.initState();
    controller=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050505))
      ..setUserAgent('SHORT SERIES TV/1.8 Android WebView ShortSeriesApp')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress:(value){
            if(mounted)setState(()=>progress=value);
          },
          onPageStarted:(url){
            if(mounted){
              setState((){
                currentUrl=url;
                loginPage=url.contains('/admin/login');
              });
            }
          },
          onPageFinished:(url) async{
            if(mounted){
              setState((){
                currentUrl=url;
                progress=100;
                loginPage=url.contains('/admin/login');
              });
            }
            await _decoratePage(url);
          },
          onNavigationRequest:(request){
            final uri=Uri.tryParse(request.url);
            if(uri==null)return NavigationDecision.prevent;
            if(uri.host=='shortseris.online'||uri.host.endsWith('.shortseris.online')){
              return NavigationDecision.navigate;
            }
            if(uri.scheme=='http'||uri.scheme=='https'){
              unawaited(launchUrl(uri,mode:LaunchMode.externalApplication));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    unawaited(_loadInitial());
  }

  Future<void> _loadInitial() async{
    final token=await Api.I.store.read(key:'token');
    final headers=<String,String>{
      'X-Short-Series-App':'android',
      'X-Requested-With':'SHORT SERIES TV',
      if(token!=null&&token.isNotEmpty)'Authorization':'Bearer $token',
    };
    await controller.loadRequest(_uri(widget.initialPath),headers:headers);
  }

  Future<void> _decoratePage(String url) async{
    final emailJson=jsonEncode(widget.userEmail);
    final js='''
      (function(){
        try{
          document.documentElement.setAttribute('data-short-series-app','android');
          var style=document.getElementById('sstv-app-webview-style');
          if(!style){
            style=document.createElement('style');
            style.id='sstv-app-webview-style';
            style.textContent='.ss-app-download{display:none!important}';
            document.head.appendChild(style);
          }
          if(location.pathname.indexOf('/admin/login')!==-1){
            var email=document.querySelector('input[type="email"],input[name="email"]');
            if(email && !email.value && ${emailJson}){
              email.value=${emailJson};
              email.dispatchEvent(new Event('input',{bubbles:true}));
              email.dispatchEvent(new Event('change',{bubbles:true}));
            }
          }
        }catch(e){}
      })();
    ''';
    try{await controller.runJavaScript(js);}catch(_){}
  }

  Future<bool> _back() async{
    if(await controller.canGoBack()){
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context){
    return WillPopScope(
      onWillPop:_back,
      child:Scaffold(
        appBar:AppBar(
          title:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(widget.title,maxLines:1,overflow:TextOverflow.ellipsis),
              if(currentUrl.isNotEmpty)
                Text(
                  currentUrl.replaceFirst('https://shortseris.online',''),
                  maxLines:1,
                  overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:10,color:Colors.white54),
                ),
            ],
          ),
          actions:[
            IconButton(
              tooltip:Api.I.ar?'الرئيسية':'Dashboard',
              onPressed:()=>controller.loadRequest(_uri('/admin')),
              icon:const Icon(Icons.dashboard_outlined),
            ),
            IconButton(
              tooltip:Api.I.ar?'تحديث':'Reload',
              onPressed:()=>controller.reload(),
              icon:const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom:progress<100
            ?PreferredSize(
                preferredSize:const Size.fromHeight(2),
                child:LinearProgressIndicator(value:progress/100),
              )
            :null,
        ),
        body:Column(
          children:[
            if(loginPage)
              Container(
                width:double.infinity,
                padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
                color:const Color(0x221DA1F2),
                child:Row(
                  children:[
                    const Icon(Icons.lock_outline_rounded,size:20),
                    const SizedBox(width:9),
                    Expanded(
                      child:Text(
                        Api.I.ar
                          ?'لأمان لوحة الويب قد يُطلب منك إدخال كلمة المرور مرة واحدة. ستبقى جلسة الإدارة محفوظة داخل التطبيق.'
                          :'For security, the web admin may request your password once. The admin session will remain in the app.',
                        style:const TextStyle(fontSize:12.5,height:1.35),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child:WebViewWidget(controller:controller)),
          ],
        ),
      ),
    );
  }
}
