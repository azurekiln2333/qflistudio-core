// Fill in the published HTTPS URLs for the app's agreements here.
//
// The privacy policy is hosted by Huawei's AGC privacy statement service; the
// compliance remediation (2026-11, §3-W3) fixes this exact address, so keep it
// verbatim. The user agreement still has no published address: the operator has
// to supply the AGC-hosted URL. Until then the entry stays visible and reports
// "协议暂未发布" instead of inventing a document.
const userAgreementUrl = '';
const privacyPolicyUrl =
    'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2045441424513576896';

const huaweiAuthenticationAgreementUrl =
    'https://privacy.consumer.huawei.com/legal/id/authentication-terms.htm?code=CN&language=zh-CN';

/// 用户协议是否已经有可打开的托管地址。
bool get userAgreementAvailable => userAgreementUrl.trim().isNotEmpty;

/// 隐私政策是否已经有可打开的托管地址。
bool get privacyPolicyAvailable => privacyPolicyUrl.trim().isNotEmpty;
