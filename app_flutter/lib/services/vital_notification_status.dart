/// 用户可见的提醒处理状态。"recorded" 仅表示服务端记录，不代表手机送达。
String vitalNotificationFeedback(dynamic rawStatus) {
  switch ((rawStatus ?? '').toString()) {
    case 'no_alert':
      return '本次未触发异常提醒。';
    case 'no_recipients':
      return '体征记录已保存，但没有可接收提醒的家属账号。';
    case 'recorded':
      return '提醒已在服务端记录，尚未确认手机送达。';
    case 'submitted':
      return '提醒已提交给推送服务，尚未确认手机送达。';
    case 'pending':
      return '提醒正在排队处理中，服务端稍后会继续处理。';
    case 'failed':
      return '提醒暂未发送成功，服务端将按重试策略继续处理。';
    case 'partial':
      return '部分提醒已处理，其余仍待处理或重试；不代表所有手机均已送达。';
    case 'suppressed':
      return '提醒因当前共享权限或来源状态而未发送。';
    default:
      return '体征记录已保存；服务端未返回可识别的提醒状态。';
  }
}
