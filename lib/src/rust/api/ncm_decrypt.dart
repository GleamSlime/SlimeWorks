// NCM 解密 FFI 绑定
// 注意：此文件需要通过 flutter_rust_bridge_codegen generate 重新生成
// 当前为手动编写的临时版本，功能完整后请运行代码生成器替换

import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

String ncmScanFilesJson({required String dir}) =>
    RustLib.instance.api.crateApiNcmDecryptNcmScanFilesJson(dir: dir);

String ncmGetProgressJson() =>
    RustLib.instance.api.crateApiNcmDecryptNcmGetProgressJson();

String ncmGetResultJson() =>
    RustLib.instance.api.crateApiNcmDecryptNcmGetResultJson();

void ncmDecryptStart({required String configJson}) =>
    RustLib.instance.api.crateApiNcmDecryptNcmDecryptStart(configJson: configJson);

void ncmDecryptCancel() =>
    RustLib.instance.api.crateApiNcmDecryptNcmDecryptCancel();
