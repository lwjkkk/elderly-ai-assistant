/// 跨平台保存字节文件：Web 触发浏览器下载，其余平台写入临时目录。
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';
