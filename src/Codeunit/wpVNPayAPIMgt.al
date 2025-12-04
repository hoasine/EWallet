codeunit 70009 "wpVNPayAPIMgt"
{
    procedure GetBaseUrl(): Text
    begin
        exit('http://localhost:5208');
    end;

    // NEW: Single blocking call that waits for payment (like VCB!)
    procedure ProcessPaymentAndWait(ReceiptNo: Code[20]; Amount: Decimal; var ResponseData: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
        TerminalID: Code[20];
        MerchantCode: Code[20];
        UserID: Code[20];
        Timeout: Integer;
        Success: Boolean;
    begin
        TerminalID := '1165089';
        MerchantCode := '1225194';
        UserID := 'POS001';
        Timeout := 300; // 5 minutes

        // This endpoint will:
        // 1. Generate QR (if not exists)
        // 2. Wait for payment on server side
        // 3. Return when complete or timeout
        ApiUrl := StrSubstNo(
            '%1/api/vnpay/process-and-wait?receiptNo=%2&amount=%3&terminal=%4&merchant=%5&userId=%6&timeout=%7',
            GetBaseUrl(),
            ReceiptNo,
            Format(Amount, 0, '<Integer>'),
            TerminalID,
            MerchantCode,
            UserID,
            Timeout
        );

        // BLOCKING CALL - waits up to 5 minutes
        // POS will show "Working on it..." automatically
        if not Client.Get(ApiUrl, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode then
            exit(false);

        Response.Content.ReadAs(ResponseText);

        if not JsonResponse.ReadFrom(ResponseText) then
            exit(false);

        // Check success
        if JsonResponse.Get('success', JsonToken) then
            Success := JsonToken.AsValue().AsBoolean()
        else
            exit(false);

        if not Success then
            exit(false);

        // Get payment data
        if JsonResponse.Get('data', JsonToken) then
            ResponseData := JsonToken.AsValue().AsText()
        else
            exit(false);

        exit(true);
    end;

    // EXISTING FUNCTIONS - Keep for QR display
    procedure GetPaymentQR(ReceiptNo: Code[20]; Amount: Decimal; var QRImageBlob: Codeunit "Temp Blob"; var CheckStatusUrl: Text): Text
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
        TerminalID: Code[20];
        MerchantCode: Code[20];
        UserID: Code[20];
        QRContent: Text;
    begin
        TerminalID := '1165089';
        MerchantCode := '1225194';
        UserID := 'POS001';

        ApiUrl := StrSubstNo(
            '%1/api/vnpay/generate?receiptNo=%2&amount=%3&terminal=%4&merchant=%5&userId=%6',
            GetBaseUrl(),
            ReceiptNo,
            Format(Amount, 0, '<Integer>'),
            TerminalID,
            MerchantCode,
            UserID
        );

        if not Client.Get(ApiUrl, Response) then
            Error('Cannot connect to VNPAY server');

        if not Response.IsSuccessStatusCode then
            Error('VNPAY API Error: %1 %2', Response.HttpStatusCode, Response.ReasonPhrase);

        Response.Content.ReadAs(ResponseText);
        if not JsonResponse.ReadFrom(ResponseText) then
            Error('Invalid JSON from VNPAY');

        if not JsonResponse.Get('qrContent', JsonToken) then
            Error('qrContent not found');

        QRContent := JsonToken.AsValue().AsText();
        if QRContent = '' then
            Error('Empty QR content');

        if JsonResponse.Get('checkStatusUrl', JsonToken) then
            CheckStatusUrl := JsonToken.AsValue().AsText()
        else
            CheckStatusUrl := StrSubstNo('%1/api/vnpay/status?receiptNo=%2', GetBaseUrl(), ReceiptNo);

        GenerateQRImageFromContent(QRContent, QRImageBlob);

        exit(QRContent);
    end;

    procedure CheckPaymentStatus(ReceiptNo: Code[20]; var StatusCode: Integer; var DataLine: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        ApiUrl: Text;
    begin
        ApiUrl := StrSubstNo('%1/api/vnpay/status?receiptNo=%2', GetBaseUrl(), ReceiptNo);

        if not Client.Get(ApiUrl, Response) then
            exit(false);

        StatusCode := Response.HttpStatusCode();

        if not Response.IsSuccessStatusCode then
            exit(false);

        Response.Content.ReadAs(ResponseText);
        if not JsonResponse.ReadFrom(ResponseText) then
            exit(false);

        if JsonResponse.Contains('data') then
            if JsonResponse.Get('data', JsonToken) then
                DataLine := JsonToken.AsValue().AsText();

        exit(true);
    end;

    local procedure GenerateQRImageFromContent(QRContent: Text; var TempBlob: Codeunit "Temp Blob")
    var
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
    begin
        if not SwissQRCodeHelper.GenerateQRCodeImage(QRContent, TempBlob) then
            Error('Failed to generate QR code image');
    end;

    procedure ConsoleLogVNPAYSuccess(ReceiptNo: Code[20]; DataLine: Text)
    var
        APP, ResponseCode, VNPDate, VNPTime, TerminalID, MerchantCode, Invoice, PosTerminalID, Amount : Text;
    begin
        Message('[VNPAY] RAW: %1', DataLine);

        ParseVNPAYData(DataLine, APP, ResponseCode, VNPDate, VNPTime, TerminalID, MerchantCode, Invoice, PosTerminalID, Amount);

        Message(
            '[VNPAY] PARSED: APP=%1, CODE=%2, DATE=%3, TIME=%4, TERM=%5, MCH=%6, INV=%7, POS=%8, AMT=%9',
            APP, ResponseCode, VNPDate, VNPTime, TerminalID, MerchantCode, Invoice, PosTerminalID, Amount
        );

        Message('[VNPAY] SUCCESS! Receipt: %1 | Amount: %2', ReceiptNo, Amount);
    end;

    procedure ParseVNPAYData(DataLine: Text; var APP: Text; var ResponseCode: Text; var Date: Text; var Time: Text; var TerminalID: Text; var MerchantCode: Text; var Invoice: Text; var PosTerminalID: Text; var Amount: Text)
    var
        DataArray: List of [Text];
        Field: Text;
        FieldParts: List of [Text];
    begin
        DataArray := DataLine.Split(';');

        foreach Field in DataArray do begin
            FieldParts := Field.Split(':');
            if FieldParts.Count >= 2 then begin
                case FieldParts.Get(1) of
                    'APP':
                        APP := FieldParts.Get(2);
                    'RESPONSE_CODE':
                        ResponseCode := FieldParts.Get(2);
                    'DATE':
                        Date := FieldParts.Get(2);
                    'TIME':
                        Time := FieldParts.Get(2);
                    'TERMINAL_ID':
                        TerminalID := FieldParts.Get(2);
                    'MERCHANT_CODE':
                        MerchantCode := FieldParts.Get(2);
                    'INVOICE':
                        Invoice := FieldParts.Get(2);
                    'PosTerminalID':
                        PosTerminalID := FieldParts.Get(2);
                    'AMOUNT':
                        Amount := FieldParts.Get(2);
                end;
            end;
        end;
    end;
    
}