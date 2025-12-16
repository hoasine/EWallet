//123

codeunit 70009 "wpVNPayAPIMgt"
{
    procedure GetPaymentQR(ReceiptNo: Code[20]; Amount: Decimal; UserID: Code[20]; var QRImageBlob: Codeunit "Temp Blob"; var CheckStatusUrl: Text): Text
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
        TerminalID: Text[20];
        MerchantCode: Text[20];
        BaseUrl: Text[250];
        QRContent: Text;
        LogLine: Text;
        StatusCode: Text;
        HttpStatus: Integer;
        POSTerminal: Record "LSC POS Terminal";
    begin
        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            Error('POS Terminal %1 not found.', POSSESSION.TerminalNo);

        if not POSTerminal."Enable VNPay Integration" then
            Error('VNPAY Integration is not enabled on this terminal.');

        TerminalID := POSTerminal."VNPAY Terminal ID";
        MerchantCode := POSTerminal."VNPAY Merchant ID";
        BaseUrl := POSTerminal."VNPAY Payment Service URL";

        if TerminalID = '' then Error('VNPAY Terminal ID is missing in POS Terminal setup.');
        if MerchantCode = '' then Error('VNPAY Merchant ID is missing in POS Terminal setup.');
        if BaseUrl = '' then Error('VNPAY Payment Service URL is missing in POS Terminal setup.');

        ApiUrl := StrSubstNo(
            '%1/api/vnpay/generate?receiptNo=%2&amount=%3&terminal=%4&merchant=%5&userId=%6',
            BaseUrl,
            ReceiptNo,
            Format(Amount, 0, '<Integer>'),
            TerminalID,
            MerchantCode,
            UserID
        );

        LogText(ReceiptNo, 'VNPAY QR Request', ApiUrl);

        if not Client.Get(ApiUrl, Response) then begin
            LogText(ReceiptNo, 'VNPAY QR Error', 'status:500;message:Cannot connect to server');
            Error('Cannot connect to VNPAY server');
        end;

        HttpStatus := Response.HttpStatusCode;
        Response.Content.ReadAs(ResponseText);

        if not JsonResponse.ReadFrom(ResponseText) then begin
            LogText(ReceiptNo, 'VNPAY QR Error',
                StrSubstNo('status:%1;message:Invalid JSON;raw:%2', HttpStatus, ResponseText));
            Error('Invalid JSON from VNPAY');
        end;

        if JsonResponse.Get('code', JsonToken) then
            StatusCode := Format(JsonToken.AsValue().AsInteger())
        else
            StatusCode := Format(HttpStatus);

        LogLine := StrSubstNo('status:%1;', StatusCode);

        if StatusCode = '200' then begin
            if JsonResponse.Get('receiptNo', JsonToken) then
                LogLine += StrSubstNo('receiptNo:%1;', JsonToken.AsValue().AsText());
            if JsonResponse.Get('amount', JsonToken) then
                LogLine += StrSubstNo('amount:%1;', JsonToken.AsValue().AsText());
            if JsonResponse.Get('qrContent', JsonToken) then begin
                QRContent := JsonToken.AsValue().AsText();
                LogLine += StrSubstNo('qrContent:%1', QRContent);
            end;

            LogText(ReceiptNo, 'VNPAY QR Response', LogLine);

            if QRContent = '' then begin
                LogText(ReceiptNo, 'VNPAY QR Error', 'status:431;message:Empty QR content');
                Error('Empty QR content');
            end;

            if JsonResponse.Get('checkStatusUrl', JsonToken) then
                CheckStatusUrl := JsonToken.AsValue().AsText()
            else
                CheckStatusUrl := StrSubstNo('%1/api/vnpay/status?receiptNo=%2', BaseUrl, ReceiptNo);

            GenerateQRImageFromContent(QRContent, QRImageBlob);
            exit(QRContent);

        end else begin
            if JsonResponse.Get('message', JsonToken) then
                LogLine += StrSubstNo('message:%1', JsonToken.AsValue().AsText())
            else
                LogLine += 'message:Unknown error';

            if JsonResponse.Get('receiptNo', JsonToken) then
                LogLine += StrSubstNo(';receiptNo:%1', JsonToken.AsValue().AsText());

            LogText(ReceiptNo, 'VNPAY QR Error', LogLine);
            Commit();
            Error('VNPAY API Error: %1', LogLine);
        end;
    end;

    procedure CheckPaymentStatus(ReceiptNo: Code[20]; var FullDataLine: Text): Code[10]
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
        StatusCode: Code[10];
        HttpStatus: Integer;
        VNPayData: Text;
        BaseUrl: Text[250];
        POSTerminal: Record "LSC POS Terminal";
    begin
        FullDataLine := '';

        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            Error('POS Terminal not found.');

        BaseUrl := POSTerminal."VNPAY Payment Service URL";
        if BaseUrl = '' then Error('VNPAY Payment Service URL not configured.');

        ApiUrl := StrSubstNo('%1/api/vnpay/status?receiptNo=%2', BaseUrl, ReceiptNo);
        LogText(ReceiptNo, 'VNPAY Status Check', ApiUrl);

        if not Client.Get(ApiUrl, Response) then begin
            LogText(ReceiptNo, 'VNPAY Status Error', 'status:999;message:Cannot connect');
            exit('999');
        end;

        HttpStatus := Response.HttpStatusCode();
        StatusCode := Format(HttpStatus);
        Response.Content.ReadAs(ResponseText);

        if not JsonResponse.ReadFrom(ResponseText) then begin
            LogText(ReceiptNo, 'VNPAY Status Error', 'status:998;message:Invalid JSON');
            exit('998');
        end;

        if JsonResponse.Get('code', JsonToken) then
            StatusCode := Format(JsonToken.AsValue().AsInteger());

        case StatusCode of
            '200':
                begin
                    if JsonResponse.Get('data', JsonToken) then begin
                        VNPayData := JsonToken.AsValue().AsText();
                        FullDataLine := VNPayData;
                    end else begin
                        FullDataLine := 'APP:VNPAY;RESPONSE_CODE:00;NO_DATA:1;';
                        LogText(ReceiptNo, 'VNPAY Status: SUCCESS', 'Payment completed (no data)');
                    end;
                end;
            '201':
                //LogText(ReceiptNo, 'VNPAY Status: PENDING', 'status:201;message:Đang xử lý');  command cuz log every 10s is so crazy

                ;
            '204':
                LogText(ReceiptNo, 'VNPAY Status: FAILED', 'status:204;message:Thanh toán thất bại hoặc hết hạn');
            else
                LogText(ReceiptNo, 'VNPAY Status: FAILED', StrSubstNo('status:%1;message:Unknown', StatusCode));
        end;

        exit(StatusCode);
    end;

    local procedure GenerateQRImageFromContent(QRContent: Text; var TempBlob: Codeunit "Temp Blob")
    var
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
    begin
        if not SwissQRCodeHelper.GenerateQRCodeImage(QRContent, TempBlob) then
            Error('Failed to generate QR code image');
    end;

    internal procedure LogText(pheader: Code[20]; ptitle: Text[50]; pText: Text[2048])
    var
        lreccom: Record "LSC Comment";
        nextlineno: Integer;
    begin
        clear(lreccom);
        lreccom.SetRange("Linked Record Id Text", pheader);
        if lreccom.FindLast() then
            nextlineno := lreccom."Line No." + 1
        else
            nextlineno := 1;

        clear(lreccom);
        lreccom."Line No." := nextlineno;
        lreccom."Linked Record Id Text" := pheader;
        lreccom.Comment := CopyStr(pText, 1, MaxStrLen(lreccom.Comment));
        lreccom."Comment Category Description" := ptitle;
        lreccom.Insert();
    end;


    procedure CancelPayment(ReceiptNo: Code[20])
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ApiUrl: Text;
        BaseUrl: Text[250];
        POSTerminal: Record "LSC POS Terminal";
        Content: HttpContent;
    begin
        if ReceiptNo = '' then
            exit;

        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            exit;

        BaseUrl := POSTerminal."VNPAY Payment Service URL";
        if BaseUrl = '' then
            exit;

        ApiUrl :=
            StrSubstNo(
                '%1/api/vnpay/cancel?receiptNo=%2',
                BaseUrl,
                ReceiptNo
            );

        LogText(ReceiptNo, 'VNPAY CANCEL REQUEST', ApiUrl);

        Client.Post(ApiUrl, Content, Response);
    end;

    var
        POSSESSION: Codeunit "LSC POS Session";
}