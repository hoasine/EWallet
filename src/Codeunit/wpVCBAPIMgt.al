codeunit 70011 "wpVCBAPIMgt"
{
    procedure GetPaymentQR(ReceiptNo: Code[20]; Amount: Decimal; UserID: Code[20]; var QRImageBlob: Codeunit "Temp Blob"; var CheckStatusUrl: Text): Text
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
        BaseUrl: Text[250];
        TerminalID: Text[20];
        MerchantCode: Text[20];
        QRPayload: Text;
        LogLine: Text;
        StatusCode: Text;
        HttpStatus: Integer;
        POSTerminal: Record "LSC POS Terminal";
        Store: Record "LSC Store";
    begin
        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            Error('POS Terminal %1 not found.', POSSESSION.TerminalNo);

        if not Store.Get(POSTerminal."Store No.") then
            Error('Store %1 not found.', POSTerminal."Store No.");

        if not Store."Enable VCB Integration" then
            Error('VCB Integration is not enabled for this store.');

        TerminalID := Store."VCB Terminal ID";
        MerchantCode := Store."VCB Merchant ID";
        BaseUrl := Store."VCB Payment Service URL";

        if TerminalID = '' then Error('VCB Terminal ID is missing in Store setup.');
        if MerchantCode = '' then Error('VCB Merchant ID is missing in Store setup.');
        if BaseUrl = '' then Error('VCB Payment Service URL is missing in Store setup.');

        ApiUrl := StrSubstNo(
            '%1/api/vcb/generate?receiptNo=%2&amount=%3&userId=%4',
            BaseUrl,
            ReceiptNo,
            Format(Amount, 0, '<Integer>'),
            UserID
        );

        LogText(ReceiptNo, 'VCB QR Request', ApiUrl);

        if not Client.Get(ApiUrl, Response) then begin
            LogText(ReceiptNo, 'VCB QR Error', 'status:500;message:Cannot connect to server');
            Error('Cannot connect to VCB server');
        end;

        HttpStatus := Response.HttpStatusCode;
        Response.Content.ReadAs(ResponseText);

        if not JsonResponse.ReadFrom(ResponseText) then begin
            LogText(ReceiptNo, 'VCB QR Error',
                StrSubstNo('status:%1;message:Invalid JSON;raw:%2', HttpStatus, ResponseText));
            Error('Invalid JSON from VCB');
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

            // VCB returns qrPayload (not qrContent like VNPAY)
            if JsonResponse.Get('qrPayload', JsonToken) then begin
                QRPayload := JsonToken.AsValue().AsText();
                LogLine += StrSubstNo('qrPayload:%1', QRPayload);
            end;

            LogText(ReceiptNo, 'VCB QR Response', LogLine);

            if QRPayload = '' then begin
                LogText(ReceiptNo, 'VCB QR Error', 'status:431;message:Empty QR payload');
                Error('Empty QR payload from VCB');
            end;

            // Build status URL for caller
            if JsonResponse.Get('checkStatusUrl', JsonToken) then
                CheckStatusUrl := JsonToken.AsValue().AsText()
            else
                CheckStatusUrl := StrSubstNo('%1/api/vcb/status?receiptNo=%2', BaseUrl, ReceiptNo);

            // Generate QR image from payload string
            GenerateQRImageFromContent(QRPayload, QRImageBlob);
            exit(QRPayload);

        end else begin
            if JsonResponse.Get('message', JsonToken) then
                LogLine += StrSubstNo('message:%1', JsonToken.AsValue().AsText())
            else
                LogLine += 'message:Unknown error';

            LogText(ReceiptNo, 'VCB QR Error', LogLine);
            Commit();
            Error('VCB API Error: %1', LogLine);
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
        BaseUrl: Text[250];
        POSTerminal: Record "LSC POS Terminal";
        Store: Record "LSC Store";
    begin
        FullDataLine := '';

        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            Error('POS Terminal not found.');

        if not Store.Get(POSTerminal."Store No.") then
            Error('Store not found.');

        BaseUrl := Store."VCB Payment Service URL";
        if BaseUrl = '' then
            Error('VCB Payment Service URL not configured.');

        ApiUrl := StrSubstNo('%1/api/vcb/status?receiptNo=%2', BaseUrl, ReceiptNo);

        if POSSESSION.GetValue('VCB_STATUS_LOGGED') = '' then begin
            LogText(ReceiptNo, 'VCB Status Check', ApiUrl);
            POSSESSION.SetValue('VCB_STATUS_LOGGED', 'YES');
        end;

        if not Client.Get(ApiUrl, Response) then begin
            LogText(ReceiptNo, 'VCB Status Error', 'status:999;message:Cannot connect');
            exit('999');
        end;

        HttpStatus := Response.HttpStatusCode();
        StatusCode := Format(HttpStatus);
        Response.Content.ReadAs(ResponseText);

        if not JsonResponse.ReadFrom(ResponseText) then begin
            LogText(ReceiptNo, 'VCB Status Error', 'status:998;message:Invalid JSON');
            exit('998');
        end;

        if JsonResponse.Get('code', JsonToken) then
            StatusCode := Format(JsonToken.AsValue().AsInteger());

        case StatusCode of
            '200':
                begin
                    if JsonResponse.Get('data', JsonToken) then begin
                        FullDataLine := JsonToken.AsValue().AsText();
                    end else begin
                        FullDataLine := 'APP:VCB;RESPONSE_CODE:00;NO_DATA:1;';
                        LogText(ReceiptNo, 'VCB Status: SUCCESS', 'Payment completed (no data)');
                    end;
                end;
            '201':
                ; // Still processing — suppress log spam every poll
            '204':
                LogText(ReceiptNo, 'VCB Status: FAILED', 'status:204;message:Payment failed or expired');
            else
                LogText(ReceiptNo, 'VCB Status: UNKNOWN', StrSubstNo('status:%1', StatusCode));
        end;

        exit(StatusCode);
    end;

    // ── CancelPayment ────────────────────────────────────────────────────────

    procedure CancelPayment(ReceiptNo: Code[20])
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        Content: HttpContent;
        ApiUrl: Text;
        BaseUrl: Text[250];
        POSTerminal: Record "LSC POS Terminal";
        Store: Record "LSC Store";
    begin
        if ReceiptNo = '' then exit;

        if not POSTerminal.Get(POSSESSION.TerminalNo) then exit;
        if not Store.Get(POSTerminal."Store No.") then exit;

        BaseUrl := Store."VCB Payment Service URL";
        if BaseUrl = '' then exit;

        ApiUrl := StrSubstNo('%1/api/vcb/cancel?receiptNo=%2', BaseUrl, ReceiptNo);

        LogText(ReceiptNo, 'VCB CANCEL REQUEST', ApiUrl);
        Client.Post(ApiUrl, Content, Response);
    end;

    // ── Private helpers ───────────────────────────────────────────────────────

    local procedure GenerateQRImageFromContent(QRContent: Text; var TempBlob: Codeunit "Temp Blob")
    var
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
    begin
        if not SwissQRCodeHelper.GenerateQRCodeImage(QRContent, TempBlob) then
            Error('Failed to generate QR code image from VCB payload');
    end;

    internal procedure LogText(pHeader: Code[20]; pTitle: Text[50]; pText: Text[2048])
    var
        lrecCom: Record "LSC Comment";
        NextLineNo: Integer;
    begin
        Clear(lrecCom);
        lrecCom.SetRange("Linked Record Id Text", pHeader);
        if lrecCom.FindLast() then
            NextLineNo := lrecCom."Line No." + 1
        else
            NextLineNo := 1;

        Clear(lrecCom);
        lrecCom."Line No." := NextLineNo;
        lrecCom."Linked Record Id Text" := pHeader;
        lrecCom.Comment := CopyStr(pText, 1, MaxStrLen(lrecCom.Comment));
        lrecCom."Comment Category Description" := pTitle;
        lrecCom.Insert();
    end;

    var
        POSSESSION: Codeunit "LSC POS Session";
}
