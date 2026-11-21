import 'package:flutter/material.dart';

import 'models.dart';

class NetrixLocalizations {
  const NetrixLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
    Locale('ja', 'JP'),
    Locale('ko', 'KR'),
  ];

  static const LocalizationsDelegate<NetrixLocalizations> delegate =
      _NetrixLocalizationsDelegate();

  /// 宿主 App 没有注册 netrix 的 delegate，所以这里回落到宿主当前语言。
  ///
  /// 宿主 `StudioLocalizations` 的语言集合是 zh-CN / zh-TW / en，本类
  /// 的目录另有 ja / ko；多出来的语言只在宿主将来扩展语言时才用到。
  static NetrixLocalizations of(BuildContext context) {
    return Localizations.of<NetrixLocalizations>(
          context,
          NetrixLocalizations,
        ) ??
        NetrixLocalizations(
          Localizations.maybeLocaleOf(context) ?? const Locale('zh', 'CN'),
        );
  }

  String _text(String key) {
    final String? region = locale.countryCode == null
        ? null
        : '${locale.languageCode}-${locale.countryCode}';
    final Map<String, String> language =
        _catalog[region] ?? _catalog[locale.languageCode] ?? _catalog['en']!;
    return language[key] ?? _catalog['en']![key] ?? key;
  }

  String get homeTitle => _text('homeTitle');
  String get homeSubtitle => _text('homeSubtitle');
  String get recentTools => _text('recentTools');
  String get recentToolsEmpty => _text('recentToolsEmpty');
  String recentToolsCount(int count) =>
      _text('recentToolsCount').replaceAll('{count}', '$count');
  String get browseAllTools => _text('browseAllTools');
  String get favoriteToolsEmpty => _text('favoriteToolsEmpty');
  String get favoriteListEmpty => _text('favoriteListEmpty');
  String favoriteToolsCount(int count) =>
      _text('favoriteToolsCount').replaceAll('{count}', '$count');
  String get viewAllTools => _text('viewAllTools');
  String get viewFavoriteTools => _text('viewFavoriteTools');
  String get noMatchingTools => _text('noMatchingTools');
  String get noMatchingToolsDescription => _text('noMatchingToolsDescription');
  String get searchTools => _text('searchTools');
  String get openTool => _text('openTool');
  String get addFavorite => _text('addFavorite');
  String get removeFavorite => _text('removeFavorite');
  String get running => _text('running');
  String get runTool => _text('runTool');
  String selectOption(String label) =>
      _text('selectOption').replaceAll('{label}', label);
  String requiredField(String label) =>
      _text('requiredField').replaceAll('{label}', label);
  String get standard => _text('standard');
  String get compact => _text('compact');
  String get oneColumn => _text('oneColumn');
  String get twoColumns => _text('twoColumns');
  String get home => _text('home');
  String get all => _text('all');
  String get favorites => _text('favorites');
  String get mine => _text('mine');
  String get settings => _text('settings');
  String get allTools => _text('allTools');
  String get favoriteTools => _text('favoriteTools');
  String get settingsBack => _text('settingsBack');
  String get openSettings => _text('openSettings');
  String get settingsDescription => _text('settingsDescription');
  String get about => _text('about');
  String get version => _text('version');
  String get versionValue => _text('versionValue');
  String get copyright => _text('copyright');
  String get feedback => _text('feedback');
  String get feedbackDescription => _text('feedbackDescription');
  String get copyEmail => _text('copyEmail');
  String get emailCopied => _text('emailCopied');
  String get website => _text('website');
  String get openWebsite => _text('openWebsite');
  String get websiteOpenFailed => _text('websiteOpenFailed');
  String get preferences => _text('preferences');
  String get preferencesDescription => _text('preferencesDescription');
  String get toolList => _text('toolList');
  String get toolListDescription => _text('toolListDescription');
  String get standardCard => _text('standardCard');
  String get compactRows => _text('compactRows');
  String get appearance => _text('appearance');
  String get appearanceDescription => _text('appearanceDescription');
  String get themeMode => _text('themeMode');
  String get followSystem => _text('followSystem');
  String get light => _text('light');
  String get dark => _text('dark');
  String get usageHistory => _text('usageHistory');
  String get usageHistoryDescription => _text('usageHistoryDescription');
  String get clearRecent => _text('clearRecent');
  String get localNetwork => _text('localNetwork');
  String get localNetworkSubtitle => _text('localNetworkSubtitle');
  String get refreshLocalNetwork => _text('refreshLocalNetwork');
  String get loadingLocalAddress => _text('loadingLocalAddress');
  String get failedLocalAddress => _text('failedLocalAddress');
  String get noAvailableAddress => _text('noAvailableAddress');
  String get noAddress => _text('noAddress');
  String get ipv4 => _text('ipv4');
  String get ipv6 => _text('ipv6');
  String get networkInterface => _text('networkInterface');
  String get publicIp => _text('publicIp');
  String get subnet => _text('subnet');
  String get gateway => _text('gateway');
  String get dns => _text('dns');
  String get mtu => _text('mtu');
  String get unavailable => _text('unavailable');
  String get externalSource => _text('externalSource');
  String get sourceUnavailable => _text('sourceUnavailable');
  String category(String key) => _text('category_$key');
  String get genericError => _text('genericError');

  String errorMessage(Object error) {
    if (error is! ToolException) return genericError;
    final String message = error.message;
    final Map<String, String> exact = <String, String>{
      'error_ipv4_segments': _text('error_ipv4_segments'),
      'error_ipv4_prefix': _text('error_ipv4_prefix'),
      'error_cidr_format': _text('error_cidr_format'),
      'error_port_range': _text('error_port_range'),
      'error_invalid_json': _text('error_invalid_json'),
      'error_unsupported_algorithm': _text('error_unsupported_algorithm'),
      'error_private_network_only': _text('error_private_network_only'),
      'error_host_limit': _text('error_host_limit'),
      'error_host_port_limit': _text('error_host_port_limit'),
    };
    final String? exactMessage = exact[message];
    if (exactMessage != null) return exactMessage;
    if (message.startsWith('error_')) {
      const Set<String> timeoutCodes = <String>{
        'error_connection_timeout',
        'error_dns_timeout',
        'error_http_timeout',
        'error_public_ip_timeout',
        'error_rdap_timeout',
        'error_tls_timeout',
        'error_websocket_timeout',
      };
      if (timeoutCodes.contains(message)) return _text('error_timeout');
      return _text('error_invalid_input');
    }
    return genericError;
  }

  static const Map<String, Map<String, String>>
  _catalog = <String, Map<String, String>>{
    'zh': <String, String>{
      'category_diagnostics': '诊断',
      'category_address': '地址与子网',
      'category_dns': 'DNS 与域名',
      'category_web': 'Web 与 API',
      'category_security': '安全与密码',
      'category_text': '文本与编码',
      'category_local': '本机网络',
      'genericError': '操作失败，请检查输入后重试。',
      'error_ipv4_segments': 'IPv4 地址必须包含四段。',
      'error_ipv4_prefix': 'IPv4 前缀必须是 0-32。',
      'error_cidr_format': 'CIDR 格式应为 192.168.1.0/24。',
      'error_port_range': '端口必须是 1-65535 之间的整数。',
      'error_invalid_json': 'JSON 格式无效。',
      'error_unsupported_algorithm': '不支持的摘要算法。',
      'error_private_network_only': '主机扫描只允许私有 IPv4 网段。',
      'error_host_limit': '主机扫描网段不能超过 256 个地址。',
      'error_host_port_limit': '主机扫描端口必须在 1-16 个之间。',
      'error_timeout': '操作超时，请稍后重试。',
      'error_invalid_input': '输入无效，请检查后重试。',
      'homeTitle': '网络工具箱',
      'homeSubtitle': '诊断连接、解析地址、测试 Web 请求并处理常见编码。',
      'recentTools': '最近使用',
      'recentToolsEmpty': '你打开过的工具会出现在这里',
      'recentToolsCount': '显示最近使用的 {count} 项',
      'browseAllTools': '浏览全部网络工具',
      'favoriteToolsEmpty': '收藏常用工具，方便下次快速打开',
      'favoriteListEmpty': '还没有收藏工具',
      'favoriteToolsCount': '显示收藏的 {count} 项',
      'viewAllTools': '查看全部工具',
      'viewFavoriteTools': '查看收藏工具',
      'noMatchingTools': '没有匹配的工具',
      'noMatchingToolsDescription': '试试其他关键词或分类。',
      'searchTools': '搜索工具',
      'openTool': '打开工具',
      'addFavorite': '添加收藏',
      'removeFavorite': '取消收藏',
      'running': '运行中',
      'runTool': '运行工具',
      'selectOption': '请选择{label}',
      'requiredField': '{label}不能为空',
      'standard': '标准',
      'compact': '紧凑',
      'oneColumn': '一列',
      'twoColumns': '两列',
      'home': '首页',
      'all': '全部',
      'favorites': '收藏',
      'mine': '我的',
      'settings': '设置',
      'allTools': '全部工具',
      'favoriteTools': '收藏工具',
      'settingsBack': '返回我的',
      'openSettings': '打开设置',
      'settingsDescription': '管理工具列表、外观主题和使用记录。',
      'about': '关于 Netrix',
      'version': '版本',
      'versionValue': '1.0.0+1',
      'copyright': 'Copyright © 2026 Azurekiln',
      'feedback': '反馈',
      'feedbackDescription': '欢迎通过邮箱提交建议或问题。',
      'copyEmail': '复制邮箱',
      'emailCopied': '邮箱已复制',
      'website': '官网',
      'openWebsite': '打开官网',
      'websiteOpenFailed': '无法打开官网，请复制上方地址到浏览器访问。',
      'preferences': '偏好设置',
      'preferencesDescription': '调整工具箱的显示方式，这些选择会自动记住。',
      'toolList': '工具列表',
      'toolListDescription': '选择工具列表的展示密度。',
      'standardCard': '标准卡片',
      'compactRows': '紧凑行',
      'appearance': '外观主题',
      'appearanceDescription': '选择应用使用的颜色模式。',
      'themeMode': '主题模式',
      'followSystem': '跟随系统',
      'light': '浅色',
      'dark': '深色',
      'usageHistory': '使用记录',
      'usageHistoryDescription': '清除首页显示的最近使用工具。',
      'clearRecent': '清除最近使用',
      'localNetwork': '本机网络',
      'localNetworkSubtitle': '按网卡显示当前设备可见的 IP 地址',
      'refreshLocalNetwork': '刷新本机地址',
      'loadingLocalAddress': '正在读取本机地址',
      'failedLocalAddress': '暂时无法读取本机地址',
      'noAvailableAddress': '未发现可用网络地址',
      'noAddress': '未发现',
      'ipv4': 'IPv4',
      'ipv6': 'IPv6',
      'networkInterface': '网络接口',
      'publicIp': '公网 IP',
      'subnet': '网段',
      'gateway': '网关',
      'dns': 'DNS',
      'mtu': 'MTU',
      'unavailable': '不可用',
      'externalSource': '来源：ipify 公网服务',
      'sourceUnavailable': '当前平台未提供此信息',
    },
    'en': <String, String>{
      'category_diagnostics': 'Diagnostics',
      'category_address': 'Address & subnet',
      'category_dns': 'DNS & domains',
      'category_web': 'Web & API',
      'category_security': 'Security & crypto',
      'category_text': 'Text & encoding',
      'category_local': 'Local network',
      'genericError': 'The operation failed. Check the input and try again.',
      'error_ipv4_segments': 'An IPv4 address must contain four segments.',
      'error_ipv4_prefix': 'The IPv4 prefix must be between 0 and 32.',
      'error_cidr_format': 'CIDR must look like 192.168.1.0/24.',
      'error_port_range': 'The port must be an integer from 1 to 65535.',
      'error_invalid_json': 'The JSON is invalid.',
      'error_unsupported_algorithm': 'The digest algorithm is unsupported.',
      'error_private_network_only':
          'Host scanning only allows private IPv4 ranges.',
      'error_host_limit':
          'The host range cannot contain more than 256 addresses.',
      'error_host_port_limit': 'Host scanning accepts 1 to 16 ports.',
      'error_timeout': 'The operation timed out. Try again later.',
      'error_invalid_input': 'The input is invalid. Check it and try again.',
      'homeTitle': 'Network toolbox',
      'homeSubtitle':
          'Diagnose connections, resolve addresses, test Web requests, and handle common encoding.',
      'recentTools': 'Recently used',
      'recentToolsEmpty': 'Tools you open will appear here',
      'recentToolsCount': 'Showing {count} recently used',
      'browseAllTools': 'Browse all network tools',
      'favoriteToolsEmpty': 'Favorite common tools for quick access next time',
      'favoriteListEmpty': 'No favorite tools yet',
      'favoriteToolsCount': 'Showing {count} favorites',
      'viewAllTools': 'View all tools',
      'viewFavoriteTools': 'View favorite tools',
      'noMatchingTools': 'No matching tools',
      'noMatchingToolsDescription': 'Try another keyword or category.',
      'searchTools': 'Search tools',
      'openTool': 'Open tool',
      'addFavorite': 'Add favorite',
      'removeFavorite': 'Remove favorite',
      'running': 'Running',
      'runTool': 'Run tool',
      'selectOption': 'Select {label}',
      'requiredField': '{label} is required',
      'standard': 'Standard',
      'compact': 'Compact',
      'oneColumn': '1 column',
      'twoColumns': '2 columns',
      'home': 'Home',
      'all': 'All',
      'favorites': 'Favorites',
      'mine': 'Me',
      'settings': 'Settings',
      'allTools': 'All tools',
      'favoriteTools': 'Favorite tools',
      'settingsBack': 'Back to me',
      'openSettings': 'Open settings',
      'settingsDescription':
          'Manage tool lists, appearance, and usage history.',
      'about': 'About Netrix',
      'version': 'Version',
      'versionValue': '1.0.0+1',
      'copyright': 'Copyright © 2026 Azurekiln',
      'feedback': 'Feedback',
      'feedbackDescription': 'Send suggestions or bug reports by email.',
      'copyEmail': 'Copy email',
      'emailCopied': 'Email copied',
      'website': 'Website',
      'openWebsite': 'Open website',
      'websiteOpenFailed':
          'Unable to open the website. Copy the address above to open it in a browser.',
      'preferences': 'Preferences',
      'preferencesDescription': 'Your display choices are saved automatically.',
      'toolList': 'Tool list',
      'toolListDescription': 'Choose the card density used by tool lists.',
      'standardCard': 'Standard cards',
      'compactRows': 'Compact rows',
      'appearance': 'Appearance',
      'appearanceDescription': 'Choose the application color mode.',
      'themeMode': 'Theme mode',
      'followSystem': 'Follow system',
      'light': 'Light',
      'dark': 'Dark',
      'usageHistory': 'Usage history',
      'usageHistoryDescription':
          'Clear recently used tools shown on the home page.',
      'clearRecent': 'Clear recent',
      'localNetwork': 'Local network',
      'localNetworkSubtitle':
          'IP addresses visible on this device, grouped by interface',
      'refreshLocalNetwork': 'Refresh local addresses',
      'loadingLocalAddress': 'Reading local addresses',
      'failedLocalAddress': 'Unable to read local addresses',
      'noAvailableAddress': 'No available network address',
      'noAddress': 'None found',
      'ipv4': 'IPv4',
      'ipv6': 'IPv6',
      'networkInterface': 'Network interface',
      'publicIp': 'Public IP',
      'subnet': 'Subnet',
      'gateway': 'Gateway',
      'dns': 'DNS',
      'mtu': 'MTU',
      'unavailable': 'Unavailable',
      'externalSource': 'Source: ipify public service',
      'sourceUnavailable': 'Not provided by the current platform',
    },
    'ja': <String, String>{
      'category_diagnostics': '診断',
      'category_address': 'アドレスとサブネット',
      'category_dns': 'DNS とドメイン',
      'category_web': 'Web と API',
      'category_security': 'セキュリティと暗号',
      'category_text': 'テキストとエンコード',
      'category_local': 'ローカルネットワーク',
      'genericError': '操作に失敗しました。入力を確認して再試行してください。',
      'error_ipv4_segments': 'IPv4 アドレスには 4 つのセグメントが必要です。',
      'error_ipv4_prefix': 'IPv4 プレフィックスは 0 から 32 の範囲です。',
      'error_cidr_format': 'CIDR は 192.168.1.0/24 の形式にしてください。',
      'error_port_range': 'ポートは 1 から 65535 の整数です。',
      'error_invalid_json': 'JSON が無効です。',
      'error_unsupported_algorithm': 'サポートされていないダイジェストアルゴリズムです。',
      'error_private_network_only': 'ホストスキャンはプライベート IPv4 範囲のみ許可します。',
      'error_host_limit': 'ホスト範囲は 256 アドレスを超えられません。',
      'error_host_port_limit': 'ホストスキャンのポート数は 1 から 16 です。',
      'error_timeout': '操作がタイムアウトしました。後でもう一度お試しください。',
      'error_invalid_input': '入力が無効です。確認して再試行してください。',
      'homeTitle': 'ネットワークツールボックス',
      'homeSubtitle': '接続の診断、アドレス解決、Web リクエストのテスト、一般的なエンコードを行います。',
      'recentTools': '最近使用したツール',
      'recentToolsEmpty': '開いたツールがここに表示されます',
      'recentToolsCount': '最近使用した {count} 件',
      'browseAllTools': 'すべてのネットワークツールを表示',
      'favoriteToolsEmpty': 'よく使うツールをお気に入りに追加できます',
      'favoriteListEmpty': 'お気に入りのツールはまだありません',
      'favoriteToolsCount': 'お気に入り {count} 件',
      'viewAllTools': 'すべてのツールを表示',
      'viewFavoriteTools': 'お気に入りを表示',
      'noMatchingTools': '一致するツールがありません',
      'noMatchingToolsDescription': '別のキーワードまたはカテゴリを試してください。',
      'searchTools': 'ツールを検索',
      'openTool': 'ツールを開く',
      'addFavorite': 'お気に入りに追加',
      'removeFavorite': 'お気に入りから削除',
      'running': '実行中',
      'runTool': 'ツールを実行',
      'selectOption': '{label}を選択してください',
      'requiredField': '{label}は必須です',
      'standard': '標準',
      'compact': 'コンパクト',
      'oneColumn': '1列',
      'twoColumns': '2列',
      'home': 'ホーム',
      'all': 'すべて',
      'favorites': 'お気に入り',
      'mine': 'マイページ',
      'settings': '設定',
      'allTools': 'すべてのツール',
      'favoriteTools': 'お気に入りのツール',
      'settingsBack': 'マイページに戻る',
      'openSettings': '設定を開く',
      'settingsDescription': 'ツール一覧、外観、使用履歴を管理します。',
      'about': 'Netrix について',
      'version': 'バージョン',
      'versionValue': '1.0.0+1',
      'copyright': 'Copyright © 2026 Azurekiln',
      'feedback': 'フィードバック',
      'feedbackDescription': '提案や問題をメールで送信できます。',
      'copyEmail': 'メールをコピー',
      'emailCopied': 'メールをコピーしました',
      'website': '公式サイト',
      'openWebsite': '公式サイトを開く',
      'websiteOpenFailed': '公式サイトを開けません。上のアドレスをコピーしてブラウザで開いてください。',
      'preferences': '環境設定',
      'preferencesDescription': '表示設定は自動的に保存されます。',
      'toolList': 'ツール一覧',
      'toolListDescription': 'ツール一覧の表示密度を選択します。',
      'standardCard': '標準カード',
      'compactRows': 'コンパクト行',
      'appearance': '外観',
      'appearanceDescription': 'カラーモードを選択します。',
      'themeMode': 'テーマモード',
      'followSystem': 'システムに従う',
      'light': 'ライト',
      'dark': 'ダーク',
      'usageHistory': '使用履歴',
      'usageHistoryDescription': 'ホームの最近のツールを消去します。',
      'clearRecent': '最近の使用を消去',
      'localNetwork': 'ローカルネットワーク',
      'localNetworkSubtitle': 'インターフェース別の IP アドレス',
      'refreshLocalNetwork': '更新',
      'loadingLocalAddress': 'アドレスを読み込み中',
      'failedLocalAddress': 'アドレスを読み込めません',
      'noAvailableAddress': '利用可能なアドレスがありません',
      'noAddress': '見つかりません',
      'ipv4': 'IPv4',
      'ipv6': 'IPv6',
      'networkInterface': 'ネットワークインターフェース',
      'publicIp': 'パブリック IP',
      'subnet': 'サブネット',
      'gateway': 'ゲートウェイ',
      'dns': 'DNS',
      'mtu': 'MTU',
      'unavailable': '利用不可',
      'externalSource': '出典: ipify 公開サービス',
      'sourceUnavailable': '現在のプラットフォームでは提供されません',
    },
    'ko': <String, String>{
      'category_diagnostics': '진단',
      'category_address': '주소 및 서브넷',
      'category_dns': 'DNS 및 도메인',
      'category_web': 'Web 및 API',
      'category_security': '보안 및 암호',
      'category_text': '텍스트 및 인코딩',
      'category_local': '로컬 네트워크',
      'genericError': '작업에 실패했습니다. 입력을 확인하고 다시 시도하세요.',
      'error_ipv4_segments': 'IPv4 주소에는 네 개의 구간이 필요합니다.',
      'error_ipv4_prefix': 'IPv4 접두사는 0에서 32 사이여야 합니다.',
      'error_cidr_format': 'CIDR은 192.168.1.0/24 형식이어야 합니다.',
      'error_port_range': '포트는 1에서 65535 사이의 정수여야 합니다.',
      'error_invalid_json': 'JSON이 올바르지 않습니다.',
      'error_unsupported_algorithm': '지원하지 않는 다이제스트 알고리즘입니다.',
      'error_private_network_only': '호스트 스캔은 사설 IPv4 범위만 허용합니다.',
      'error_host_limit': '호스트 범위는 256개 주소를 초과할 수 없습니다.',
      'error_host_port_limit': '호스트 스캔 포트는 1개에서 16개까지입니다.',
      'error_timeout': '작업 시간이 초과되었습니다. 나중에 다시 시도하세요.',
      'error_invalid_input': '입력이 올바르지 않습니다. 확인 후 다시 시도하세요.',
      'homeTitle': '네트워크 도구 상자',
      'homeSubtitle': '연결 진단, 주소 확인, Web 요청 테스트와 일반적인 인코딩을 처리합니다.',
      'recentTools': '최근 사용',
      'recentToolsEmpty': '열어 본 도구가 여기에 표시됩니다',
      'recentToolsCount': '최근 사용 {count}개 표시',
      'browseAllTools': '모든 네트워크 도구 보기',
      'favoriteToolsEmpty': '자주 쓰는 도구를 즐겨찾기에 추가하세요',
      'favoriteListEmpty': '아직 즐겨찾기 도구가 없습니다',
      'favoriteToolsCount': '즐겨찾기 {count}개 표시',
      'viewAllTools': '모든 도구 보기',
      'viewFavoriteTools': '즐겨찾기 보기',
      'noMatchingTools': '일치하는 도구가 없습니다',
      'noMatchingToolsDescription': '다른 키워드나 카테고리를 시도해 보세요.',
      'searchTools': '도구 검색',
      'openTool': '도구 열기',
      'addFavorite': '즐겨찾기 추가',
      'removeFavorite': '즐겨찾기 삭제',
      'running': '실행 중',
      'runTool': '도구 실행',
      'selectOption': '{label}을(를) 선택하세요',
      'requiredField': '{label}은(는) 필수입니다',
      'standard': '표준',
      'compact': '간결',
      'oneColumn': '1열',
      'twoColumns': '2열',
      'home': '홈',
      'all': '전체',
      'favorites': '즐겨찾기',
      'mine': '내 정보',
      'settings': '설정',
      'allTools': '모든 도구',
      'favoriteTools': '즐겨찾기 도구',
      'settingsBack': '내 정보로 돌아가기',
      'openSettings': '설정 열기',
      'settingsDescription': '도구 목록, 모양과 사용 기록을 관리합니다.',
      'about': 'Netrix 정보',
      'version': '버전',
      'versionValue': '1.0.0+1',
      'copyright': 'Copyright © 2026 Azurekiln',
      'feedback': '피드백',
      'feedbackDescription': '제안이나 문제를 이메일로 보내 주세요.',
      'copyEmail': '이메일 복사',
      'emailCopied': '이메일이 복사되었습니다',
      'website': '공식 웹사이트',
      'openWebsite': '웹사이트 열기',
      'websiteOpenFailed': '웹사이트를 열 수 없습니다. 위 주소를 복사해 브라우저에서 열어 주세요.',
      'preferences': '환경설정',
      'preferencesDescription': '표시 설정은 자동으로 저장됩니다.',
      'toolList': '도구 목록',
      'toolListDescription': '도구 목록의 표시 밀도를 선택합니다.',
      'standardCard': '표준 카드',
      'compactRows': '간결한 행',
      'appearance': '모양',
      'appearanceDescription': '앱 색상 모드를 선택합니다.',
      'themeMode': '테마 모드',
      'followSystem': '시스템 설정 따르기',
      'light': '밝게',
      'dark': '어둡게',
      'usageHistory': '사용 기록',
      'usageHistoryDescription': '홈의 최근 도구를 지웁니다.',
      'clearRecent': '최근 기록 지우기',
      'localNetwork': '로컬 네트워크',
      'localNetworkSubtitle': '인터페이스별 IP 주소',
      'refreshLocalNetwork': '새로고침',
      'loadingLocalAddress': '주소를 읽는 중',
      'failedLocalAddress': '주소를 읽을 수 없습니다',
      'noAvailableAddress': '사용 가능한 주소가 없습니다',
      'noAddress': '없음',
      'ipv4': 'IPv4',
      'ipv6': 'IPv6',
      'networkInterface': '네트워크 인터페이스',
      'publicIp': '공인 IP',
      'subnet': '서브넷',
      'gateway': '게이트웨이',
      'dns': 'DNS',
      'mtu': 'MTU',
      'unavailable': '사용할 수 없음',
      'externalSource': '출처: ipify 공개 서비스',
      'sourceUnavailable': '현재 플랫폼에서 제공하지 않음',
    },
    'zh-TW': <String, String>{
      'category_diagnostics': '診斷',
      'category_address': '位址與網段',
      'category_dns': 'DNS 與網域',
      'category_web': 'Web 與 API',
      'category_security': '安全性與密碼',
      'category_text': '文字與編碼',
      'category_local': '本機網路',
      'genericError': '操作失敗，請檢查輸入後再試。',
      'error_ipv4_segments': 'IPv4 位址必須包含四段。',
      'error_ipv4_prefix': 'IPv4 前綴必須介於 0 到 32。',
      'error_cidr_format': 'CIDR 格式應為 192.168.1.0/24。',
      'error_port_range': '連接埠必須是 1 到 65535 之間的整數。',
      'error_invalid_json': 'JSON 格式無效。',
      'error_unsupported_algorithm': '不支援的摘要演算法。',
      'error_private_network_only': '主機掃描只允許私有 IPv4 網段。',
      'error_host_limit': '主機網段不能超過 256 個位址。',
      'error_host_port_limit': '主機掃描連接埠必須介於 1 到 16 個。',
      'error_timeout': '操作逾時，請稍後再試。',
      'error_invalid_input': '輸入無效，請檢查後再試。',
      'homeTitle': '網路工具箱',
      'homeSubtitle': '診斷連線、解析位址、測試 Web 請求並處理常見編碼。',
      'recentTools': '最近使用',
      'recentToolsEmpty': '你開啟過的工具會出現在這裡',
      'recentToolsCount': '顯示最近使用的 {count} 項',
      'browseAllTools': '瀏覽全部網路工具',
      'favoriteToolsEmpty': '收藏常用工具，方便下次快速開啟',
      'favoriteListEmpty': '還沒有收藏工具',
      'favoriteToolsCount': '顯示收藏的 {count} 項',
      'viewAllTools': '檢視全部工具',
      'viewFavoriteTools': '檢視收藏工具',
      'noMatchingTools': '沒有符合的工具',
      'noMatchingToolsDescription': '請嘗試其他關鍵字或分類。',
      'searchTools': '搜尋工具',
      'openTool': '開啟工具',
      'addFavorite': '加入收藏',
      'removeFavorite': '取消收藏',
      'running': '執行中',
      'runTool': '執行工具',
      'selectOption': '請選擇{label}',
      'requiredField': '{label}不可為空',
      'standard': '標準',
      'compact': '精簡',
      'oneColumn': '一欄',
      'twoColumns': '兩欄',
      'home': '首頁',
      'all': '全部',
      'favorites': '收藏',
      'mine': '我的',
      'settings': '設定',
      'allTools': '全部工具',
      'favoriteTools': '收藏工具',
      'settingsBack': '返回我的',
      'openSettings': '開啟設定',
      'settingsDescription': '管理工具列表、外觀主題與使用記錄。',
      'about': '關於 Netrix',
      'version': '版本',
      'versionValue': '1.0.0+1',
      'copyright': 'Copyright © 2026 Azurekiln',
      'feedback': '回饋',
      'feedbackDescription': '歡迎透過電子郵件提交建議或問題。',
      'copyEmail': '複製電子郵件',
      'emailCopied': '電子郵件已複製',
      'website': '官方網站',
      'openWebsite': '開啟官方網站',
      'websiteOpenFailed': '無法開啟官方網站，請複製上方位址並在瀏覽器中開啟。',
      'preferences': '偏好設定',
      'preferencesDescription': '顯示選項會自動記住。',
      'toolList': '工具列表',
      'toolListDescription': '選擇工具列表的顯示密度。',
      'standardCard': '標準卡片',
      'compactRows': '精簡列',
      'appearance': '外觀主題',
      'appearanceDescription': '選擇應用程式的色彩模式。',
      'themeMode': '主題模式',
      'followSystem': '跟隨系統',
      'light': '淺色',
      'dark': '深色',
      'usageHistory': '使用記錄',
      'usageHistoryDescription': '清除首頁顯示的最近使用工具。',
      'clearRecent': '清除最近使用',
      'localNetwork': '本機網路',
      'localNetworkSubtitle': '按網路介面顯示目前裝置可見的 IP 位址',
      'refreshLocalNetwork': '重新整理本機位址',
      'loadingLocalAddress': '正在讀取本機位址',
      'failedLocalAddress': '暫時無法讀取本機位址',
      'noAvailableAddress': '找不到可用的網路位址',
      'noAddress': '未找到',
      'ipv4': 'IPv4',
      'ipv6': 'IPv6',
      'networkInterface': '網路介面',
      'publicIp': '公網 IP',
      'subnet': '網段',
      'gateway': '閘道',
      'dns': 'DNS',
      'mtu': 'MTU',
      'unavailable': '無法使用',
      'externalSource': '來源：ipify 公開服務',
      'sourceUnavailable': '目前平台未提供此資訊',
    },
  };
}

class _NetrixLocalizationsDelegate
    extends LocalizationsDelegate<NetrixLocalizations> {
  const _NetrixLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => NetrixLocalizations.supportedLocales.any(
    (Locale item) => item.languageCode == locale.languageCode,
  );

  @override
  Future<NetrixLocalizations> load(Locale locale) async {
    return NetrixLocalizations(locale);
  }

  @override
  bool shouldReload(_NetrixLocalizationsDelegate old) => false;
}
