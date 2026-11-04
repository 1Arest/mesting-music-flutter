# 1.0.33 底部遮挡排查与修复范围

2026-11-01，Asia/Shanghai。代码检查覆盖153处原有滚动声明，并另外检查待播队列的可重排列表。此表记录代码审查范围，不代表153页逐一真机验收。

## 公共问题

主BetaMusicShell已有玻璃导航/播放胶囊，却没有向正文提供BetaContentInsets；页面在主壳中会跳过独立底栏包装，因此更新说明、公共表单及通用接口页读取到底距0。独立页原有170dp基础避让在主壳中缺失。现在主壳和独立包装共用同一公式：170dp + 2×clamp(24字号的增量,0,28) + 系统viewPadding.bottom，滚动收起底栏时仍保留展开状态预算，避免末项被再次展开覆盖。

业务页面通过musicPaddingOf/musicBottomOf在可滚动内容内部预留，保留原有更大底距。Stable沿用原底距；没有音乐底栏的弹层/聊天输入区不套该高度。装扮页的Beta留白移入滚动内容，背景仍绘制到玻璃后方。独立队列路由增加内部末尾留白，弹层和播放器内队列保留18dp。

## 已检查入口

| 代码位置（修复前行号） | 处理/核对 |
| --- | --- |
| `lib/shared/widgets/beta_choice_field.dart:49` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/shared/widgets/beta_glass_scroll_body.dart:23` | 共享正文；读取本次补齐的主壳/独立页安全底距 |
| `lib/shared/widgets/beta_text_editing.dart:258` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/audiobooks/audiobooks_page.dart:189` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/audiobooks/audiobooks_page.dart:278` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/audiobooks/audiobooks_page.dart:579` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/downloads/audio_downloads_page.dart:235` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/downloads/audio_download_quality.dart:95` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/kugou_together/together_page.dart:57` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/kugou_together/together_page.dart:336` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/music_platform/listening_sync_page.dart:17` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/recognition/song_recognition_page.dart:191` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/themes/theme_gallery_page.dart:198` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/themes/theme_gallery_page.dart:261` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/themes/theme_gallery_page.dart:801` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/themes/theme_gallery_page.dart:956` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/themes/theme_gallery_page.dart:1376` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/themes/theme_gallery_page.dart:1674` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/social/presentation/chat_page.dart:362` | 已核对所属视口和既有底距；保留专用安全区/内嵌结构 |
| `lib/features/social/presentation/chat_page.dart:393` | 已核对所属视口和既有底距；保留专用安全区/内嵌结构 |
| `lib/features/social/presentation/chat_page.dart:2690` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/social/presentation/chat_page.dart:4223` | 已核对所属视口和既有底距；保留专用安全区/内嵌结构 |
| `lib/features/social/presentation/listen_together_sheet.dart:164` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/listen_together_sheet.dart:180` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/listen_together_sheet.dart:191` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/listen_together_sheet.dart:329` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/listen_together_sheet.dart:345` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/public_profile_page.dart:41` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/public_profile_page.dart:52` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/saved_messages_page.dart:155` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/saved_messages_page.dart:165` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/saved_messages_page.dart:249` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/saved_messages_page.dart:259` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_connections_page.dart:175` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_connections_page.dart:186` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_connections_page.dart:215` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_messages_page.dart:39` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_messages_page.dart:49` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/social_messages_page.dart:64` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/social/presentation/track_share_sheet.dart:88` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/track_share_sheet.dart:104` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/social/presentation/track_share_sheet.dart:115` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/settings/presentation/frame_diagnostics_page.dart:171` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/settings/presentation/music_sleep_timer_sheet.dart:99` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/settings/presentation/settings_page.dart:51` | 已有210dp + 字号增量 + 系统安全区，满足公共底距；保留 |
| `lib/features/search/presentation/apple_search_results.dart:51` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/search/presentation/beta_category_search_results.dart:203` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/search/presentation/music_search_page.dart:480` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/search/presentation/music_search_page.dart:785` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/search/presentation/music_search_page.dart:1094` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/search/presentation/music_search_page.dart:1170` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/search/presentation/music_search_page.dart:1777` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/search/presentation/music_search_page.dart:1884` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/recommendation/presentation/recommendation_page.dart:120` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/recommendation/presentation/recommendation_page.dart:1277` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/queue/presentation/beta_playback_queue.dart:168` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/queue/presentation/queue_page.dart:167` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/profile/presentation/profile_background_page.dart:333` | 已核对所属视口和既有底距；保留专用安全区/内嵌结构 |
| `lib/features/profile/presentation/profile_background_page.dart:368` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/profile/presentation/profile_edit_page.dart:87` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/profile/presentation/profile_edit_page.dart:788` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/profile/presentation/profile_edit_page.dart:803` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/profile/presentation/profile_page.dart:174` | Beta转入公共平台个人页；Stable原视口保留 |
| `lib/features/profile/presentation/social_status_sheet.dart:121` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/profile/presentation/social_status_sheet.dart:145` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/profile/presentation/social_status_sheet.dart:362` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/playlists/presentation/add_to_playlist_sheet.dart:151` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/playlists/presentation/playlist_detail_page.dart:327` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/playlists/presentation/playlist_detail_page.dart:1451` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/playlists/presentation/playlist_editor_dialog.dart:237` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/player/presentation/music_hub_top_bar.dart:381` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/music_platform/netease/netease_account_overview.dart:128` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_comment_hugs_page.dart:108` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_features_page.dart:413` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_membership_page.dart:96` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_playback_settings_page.dart:44` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_playlist_import_page.dart:103` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_user_page.dart:245` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/netease_user_page.dart:441` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/apple_hot_search.dart:31` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/music_platform/presentation/beta_personal_profile.dart:93` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/music_effects_page.dart:210` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_account_page.dart:259` | 弹层列表或BetaGlassScrollBody正文；由所属包装避让 |
| `lib/features/music_platform/presentation/platform_catalog_detail_page.dart:171` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_comments_page.dart:513` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_discovery_page.dart:52` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_discovery_page.dart:338` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_library_page.dart:39` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_library_page.dart:178` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_quality_button.dart:91` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/music_platform/presentation/platform_recommendations_page.dart:403` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_reward_calendar.dart:147` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_reward_calendar.dart:296` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/music_platform/presentation/platform_search_landing.dart:96` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/platform_search_landing.dart:218` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/music_platform/presentation/platform_search_landing.dart:419` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/presentation/unified_reward_page.dart:147` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/fallback/netease_source_picker.dart:167` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/music_platform/netease/full/netease_comment_entry_page.dart:96` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/full/netease_entity_picker.dart:296` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/full/netease_full_page.dart:293` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/full/netease_full_page.dart:823` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/full/netease_full_page.dart:1406` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_messages_page.dart:230` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_messages_page.dart:492` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_messages_page.dart:761` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_messages_page.dart:1310` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_messages_page.dart:1344` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_message_card_view.dart:103` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/music_platform/netease/messages/netease_message_diagnostic_action.dart:27` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/music_platform/netease/together/netease_together_panel.dart:118` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/lyrics/presentation/lyrics_panel.dart:95` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/lyrics/presentation/lyrics_panel.dart:171` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/local_music/presentation/local_music_page.dart:268` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/local_music/presentation/local_music_page.dart:280` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/library/presentation/music_home_page.dart:136` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/library/presentation/music_home_page.dart:346` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/library/presentation/music_home_page.dart:497` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/legal/presentation/disclaimer_dialog.dart:243` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/legal/presentation/disclaimer_dialog.dart:486` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/legal/presentation/disclaimer_dialog.dart:591` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/legal/presentation/disclaimer_dialog.dart:825` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/legal/presentation/legal_documents_page.dart:14` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/legal/presentation/legal_documents_page.dart:83` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/history/presentation/listening_history_page.dart:224` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/history/presentation/listening_history_page.dart:459` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/experience/presentation/beta_now_playing_page.dart:447` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/experience/presentation/cover_player_page.dart:489` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/experience/presentation/editorial_widgets.dart:43` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/experience/presentation/editorial_widgets.dart:331` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/experience/presentation/immersive_lyrics.dart:143` | 完整播放器/歌词专用视口；不添加主音乐栏占位 |
| `lib/features/experience/presentation/listening_replay_page.dart:106` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/experience/presentation/music_functions_page.dart:181` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/experience/presentation/music_home_catalogues.dart:214` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/experience/presentation/music_landing_page.dart:377` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/experience/presentation/music_library_page.dart:49` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/experience/presentation/playback_pill_menu.dart:85` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/experience/presentation/player_more_menu.dart:75` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/experience/presentation/player_output_dialog.dart:67` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/discover/presentation/curated_playlist_page.dart:51` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/discover/presentation/curated_playlist_page.dart:346` | 横向/内嵌滚动；由外层正文负责底部避让 |
| `lib/features/discover/presentation/discover_page.dart:29` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/auth/presentation/account_bindings_page.dart:60` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/auth/presentation/account_bindings_page.dart:237` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/auth/presentation/account_deletion_page.dart:77` | 改用公共动态底距，或保留已有专用视口/输入区；具体差异见源码 |
| `lib/features/auth/presentation/auth_page.dart:195` | 欢迎/登录/引导独立视口，无音乐底栏；保留安全区/键盘滚动 |
| `lib/features/auth/presentation/beta_onboarding_page.dart:319` | 欢迎/登录/引导独立视口，无音乐底栏；保留安全区/键盘滚动 |
| `lib/features/auth/presentation/beta_welcome_page.dart:90` | 欢迎/登录/引导独立视口，无音乐底栏；保留安全区/键盘滚动 |
| `lib/features/auth/presentation/forgot_password_page.dart:65` | 欢迎/登录/引导独立视口，无音乐底栏；保留安全区/键盘滚动 |
| `lib/features/app_update/presentation/app_update_sheet.dart:107` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/app_update/presentation/beta_app_update_sheet.dart:149` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |
| `lib/features/app_update/presentation/release_history_page.dart:21` | 自身已读取公共底距；本次补齐其真实主壳祖先 |
| `lib/features/app_update/presentation/release_notes_sheet.dart:25` | 独立弹层/菜单；检查自身安全区和滚动，无主音乐底栏叠放 |

## 验证边界

新增主机测试直接挂载BetaMusicShell和真实底栏，分别检查历史1.0.1折叠/展开后的整项矩形、普通/窄屏大字号、34dp系统安全区、主壳/独立页，以及账号概览和公共表单末项。比较的是实际控件矩形，不只断言padding常量。地区回归检查真实CupertinoPicker的选中索引、列表首项和确认/取消返回值。

所有画面为Flutter主机合成渲染，不代表手机覆盖安装、系统返回/TalkBack、真实业务及GPU/FPS通过。主机也没有逐一开启每个网络页面；需安装后按INSTALL逐项验收。
