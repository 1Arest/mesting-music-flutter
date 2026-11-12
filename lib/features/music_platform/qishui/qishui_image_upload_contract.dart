/// Shared private ImageX protocol constants, recovered from the retained
/// official uploader rather than a public SDK's regional defaults.
abstract final class QishuiImageUploadContract {
  static const apiPath = '/top/v1';
  static const service = 'imagex';

  // This unusual literal is intentional: the official native base constructor
  // copies these nine bytes into the region field. Native key 109 passes that
  // field through JNI to AWSV4Auth.Builder.regionName without transformation.
  // UploadImageObservable's normal image path does not override it. An empty
  // region, or a guessed public AWS/Volcengine region, signs different bytes.
  static const region = 'sdwdmwlll';
}
