declare module 'africastalking' {
  interface AfricasTalkingConfig {
    apiKey: string;
    username: string;
  }

  interface SMSRecipient {
    number: string;
    status: string;
    statusCode: number;
    messageId: string;
    cost: string;
  }

  interface SMSMessageData {
    Message: string;
    Recipients: SMSRecipient[];
  }

  interface SMSResponse {
    SMSMessageData: SMSMessageData;
  }

  interface SMSOptions {
    to: string[];
    message: string;
    from?: string;
  }

  interface SMS {
    send(options: SMSOptions): Promise<SMSResponse>;
  }

  interface AirtimeRecipient {
    phoneNumber: string;
    currencyCode: string;
    amount: number;
  }

  interface AirtimeOptions {
    recipients: AirtimeRecipient[];
  }

  interface Airtime {
    send(options: AirtimeOptions): Promise<any>;
  }

  interface AfricasTalkingClient {
    SMS: SMS;
    AIRTIME: Airtime;
  }

  function AfricasTalking(config: AfricasTalkingConfig): AfricasTalkingClient;

  export = AfricasTalking;
}
