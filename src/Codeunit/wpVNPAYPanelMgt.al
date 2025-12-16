codeunit 70008 "wpVNPAYPanelMgt"
{
    SingleInstance = true;
    TableNo = "LSC POS Menu Line";

    trigger OnRun()
    begin
        Rec.Processed := true;
        GlobalRec := Rec;

        if IsWaitingForAutoCheck then
            CheckAutoCheckTimer();

        if GlobalRec."Pos Event Type" = GlobalRec."Pos Event Type"::BUTTONPRESS then
            case GlobalRec.Parameter of
                'CHECK':
                    ManualCheckStatus();
                'OK':
                    CancelVNPAY();
                else
                    GlobalRec.Processed := false;
            end
        else
            GlobalRec.Processed := false;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnBeforeInit', '', false, false)]
    local procedure OnBeforeInit(var POSTransaction: Record "LSC POS Transaction")
    begin
        VnpayStatus_g := '';
        VnpayType_g := '';
        VnpayAmount_g := 0;
        Balance_g := 0;
        TenderTypeCode_g := '';
        IsWaitingForAutoCheck := false;
        AutoCheckCount := 0;

        POSSESSION.SetValue('VNPAYRECEIPT', '');
        POSSESSION.SetValue('VNPAYBALANCE', '');
        POSSESSION.SetValue('VNPAYTENDER', '');
        POSSESSION.SetValue('VNPAYStatus', '');
        POSSESSION.SetValue('VNPAYType', '');
        POSSESSION.SetValue('VNPAYAmount', '');
        POSTransaction_g := POSTransaction;
        if POSTerminal_g.Get(POSSESSION.TerminalNo) then;
    end;

    local procedure ManualCheckStatus()
    var
        StatusCode: Code[10];
        DummyLine: Text;
    begin
        StatusCode := VNPAYAPI.CheckPaymentStatus(POSTransaction_g."Receipt No.", DummyLine);

        case StatusCode of
            '200':
                begin
                    cuPosTrans.TenderKeyPressedEx(TenderTypeCode_g, Format(vnpayAmount_g));
                    vnpayStatus_g := 'PAID';
                    POSSESSION.SetValue('VNPAYStatus', vnpayStatus_g);
                    POSGUI.PosMessage('SUCCESS!');
                    Sleep(2000);
                    CloseVNPAYPanel();

                end;
            '201':
                Message('WAITING FOR CUSTOMER PAYMENT...');
            else
                Message('PAYMENT FAILED OR EXPIRED');
        end;
    end;

    local procedure StartAutoCheck()
    begin
        IsWaitingForAutoCheck := true;
        AutoCheckCount := 0;
        LastAutoCheckTime := CurrentDateTime;
    end;

    local procedure StopAutoCheck()
    begin
        IsWaitingForAutoCheck := false;
        AutoCheckCount := 0;
    end;

    local procedure CheckAutoCheckTimer()
    var
        Elapsed: Integer;
        WaitTime: Integer;
        firstCheck: Integer;
        intervalCheck: Integer;
        maxRetries: Integer;
    begin

        firstCheck := POSTerminal_g."VNPAY First Check Delay Sec";
        intervalCheck := POSTerminal_g."VNPAY Check Interval Sec";
        maxRetries := POSTerminal_g."VNPay Max Retries";

        if firstCheck = 0 then Error('VNPAY First Check is missing in POS Terminal setup.');
        if intervalCheck = 0 then Error('VNPAY Check Interval is missing in POS Terminal setup.');
        if maxRetries = 0 then Error('VNPAY Max Retries is missing in POS Terminal setup.');

        if not IsWaitingForAutoCheck then exit;

        Elapsed := (CurrentDateTime - LastAutoCheckTime) div 1000;

        if AutoCheckCount = 0 then
            WaitTime := firstCheck
        else
            WaitTime := intervalCheck;

        if Elapsed >= WaitTime then begin
            LastAutoCheckTime := CurrentDateTime;
            AutoCheckCount += 1;

            if AutoCheckCount > maxRetries then begin
                StopAutoCheck();
                exit;
            end;

            PerformAutoCheck();
        end;
    end;

    local procedure PerformAutoCheck()
    var
        StatusCode: Code[10];
        FullDataLine: Text;
    begin
        if POSTransaction_g."Receipt No." = '' then begin
            StopAutoCheck();
            exit;
        end;

        StatusCode := VNPAYAPI.CheckPaymentStatus(POSTransaction_g."Receipt No.", FullDataLine);

        case StatusCode of
            '200':
                begin

                    POSSESSION.SetValue('VNPAY_FULL_DATA', FullDataLine);

                    cuPosTrans.TenderKeyPressedEx(TenderTypeCode_g, Format(vnpayAmount_g));
                    vnpayStatus_g := 'PAID';
                    POSSESSION.SetValue('VNPAYStatus', vnpayStatus_g);
                    POSGUI.PosMessage('PAYMENT SUCCESS!');
                    Sleep(1500);
                    CloseVNPAYPanel();
                end;
            '201':
                ; //No log cuz check status every 10s is so many logs
            else begin
                StopAutoCheck();
                POSGUI.PosMessage('PAYMENT FAILED OR EXPIRED');
                CloseVNPAYPanel();
            end;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnBeforeInsertPaymentLine', '', false, false)]
    local procedure OnBeforeInsertPaymentLine(
        var POSTransaction: Record "LSC POS Transaction";
        var POSTransLine: Record "LSC POS Trans. Line";
        var CurrInput: Text;
        var TenderTypeCode: Code[10];
        Balance: Decimal;
        PaymentAmount: Decimal;
        STATE: Code[10];
        var isHandled: Boolean)
    begin
        if TenderTypeCode <> '87' then
            exit;

        if POSSESSION.GetValue('VNPAYRECEIPT') <> POSTransaction."Receipt No." then begin
            vnpayStatus_g := '';
            POSSESSION.SetValue('VNPAYStatus', '');
            POSSESSION.SetValue('VNPAYRECEIPT', '');
        end else
            vnpayStatus_g := POSSESSION.GetValue('VNPAYStatus');

        if vnpayStatus_g = '' then begin
            if InsertTenderAmount(POSTransaction, PaymentAmount) then begin
                TenderTypeCode_g := TenderTypeCode;
                vnpayAmount_g := PaymentAmount;
                POSSESSION.SetValue('VNPAYRECEIPT', POSTransaction."Receipt No.");
                isHandled := true;
            end;
        end else
            isHandled := false;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnAfterInsertPaymentLine', '', false, false)]
    local procedure OnAfterInsertPaymentLine_VNPAY(
    var POSTransaction: Record "LSC POS Transaction";
    var POSTransLine: Record "LSC POS Trans. Line";
    var CurrInput: Text;
    var TenderTypeCode: Code[10];
    var SkipCommit: Boolean)
    var
        CardEntry: Record "LSC POS Card Entry";
        NextEntryNo: Integer;
        FullDataLine: Text;
        ResponseCode: Code[10];
        DateStr: Text[6];
        TimeStr: Text[6];
        TerminalID: Text[20];
        MerchantCode: Text[20];
        Invoice: Code[20];
        PosTerminalID: Code[20];
        Amount: Decimal;
        TransNo: Integer;
    begin
        if TenderTypeCode <> '87' then exit;
        if POSTransLine."Entry Type" <> POSTransLine."Entry Type"::Payment then exit;

        if POSSESSION.GetValue('VNPAY_CARD_ENTRY_DONE') = 'YES' then exit;


        FullDataLine := POSSESSION.GetValue('VNPAY_FULL_DATA');
        if FullDataLine = '' then
            FullDataLine := StrSubstNo('APP:VNPAY;RESPONSE_CODE:00;INVOICE:%1;AMOUNT:%2;',
                                      POSTransaction."Receipt No.", Format(POSTransLine.Amount));

        ParseVNPAYDataLine(FullDataLine, ResponseCode, DateStr, TimeStr,
                           TerminalID, MerchantCode, Invoice, PosTerminalID, Amount);

        CardEntry.SetRange("Store No.", POSTransaction."Store No.");
        CardEntry.SetRange("POS Terminal No.", POSTransaction."POS Terminal No.");
        if CardEntry.FindLast() then
            NextEntryNo := CardEntry."Entry No." + 1
        else
            NextEntryNo := 1;

        CardEntry.Init();
        CardEntry."Store No." := POSTransaction."Store No.";
        CardEntry."POS Terminal No." := POSTransaction."POS Terminal No.";
        CardEntry."Entry No." := NextEntryNo;
        CardEntry."Line No." := POSTransLine."Line No.";
        CardEntry."Receipt No." := POSTransaction."Receipt No.";
        CardEntry."Tender Type" := '87';
        CardEntry."Transaction Type" := CardEntry."Transaction Type"::Sale;

        CardEntry."Card Number" := 'VNPAY_QR';
        CardEntry."Card Type" := 'VNPAY';
        CardEntry."Res.code" := ResponseCode;
        CardEntry."EFT Auth.code" := 'VNPAY';
        CardEntry."EFT Merchant No." := MerchantCode;
        CardEntry."EFT Trans. Date" := DateStr;
        CardEntry."EFT Trans. Time" := TimeStr;
        CardEntry.Amount := Amount;
        CardEntry."EFT Transaction ID" := Invoice;
        CardEntry."EFT Currency" := 'VND';
        CardEntry."EFT Terminal ID" := TerminalID;
        CardEntry."Auth. Source Code" := 'VNPAY';

        CardEntry.Date := Today;
        CardEntry.Time := Time;
        CardEntry."Authorisation Ok" := (ResponseCode = '00');

        CardEntry.Insert(true);



        TransNo := CardEntry."Transaction No.";
        FullDataLine += StrSubstNo('TransNo:%1;', TransNo);

        VNPAYAPI.LogText(POSTransaction."Receipt No.", 'VNPAY Complete Data', FullDataLine);

        POSSESSION.SetValue('VNPAY_CARD_ENTRY_DONE', 'YES');
    end;

    local procedure InsertTenderAmount(var POSTransaction: Record "LSC POS Transaction"; var TransAmount: Decimal): Boolean
    var
        POSTerminal: Record "LSC POS Terminal";
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
        PlaylistHdr: Record "LSC POS Media Playlist Header";
        QRUrl: Text;
        RetailImageLink: Record "LSC Retail Image Link";
        RetailImage: Record "LSC Retail Image";
        TempBLOB: Codeunit "Temp Blob";
        ImageInStream: InStream;
        CheckStatusUrl: Text;
        UserID: Code[20];
        ImageID: Code[20];
    begin
        if POSTransaction."Sale Is Return Sale" then exit;

        if not POSTerminal.Get(POSTransaction."POS Terminal No.") then
            Error('POS Terminal %1 not found.', POSTransaction."POS Terminal No.");

        if not POSTerminal."Enable VNPay Integration" then
            Error('VNPAY is not enabled on this terminal.');

        POSSESSION.SetValue('RECEIPTNO', POSTransaction."Receipt No.");

        if POSTerminal_g."No." <> '' then
            UserID := POSTerminal_g."No."
        else
            UserID := POSSESSION.TerminalNo;

        QRUrl := VNPAYAPI.GetPaymentQR(POSTransaction."Receipt No.", TransAmount, UserID, TempBlob, CheckStatusUrl);

        if not SwissQRCodeHelper.GenerateQRCodeImage(QRUrl, TempBlob) then
            Error('Failed to generate VNPay QR');


        ImageID := 'VNPAY';


        if not PlaylistHdr.Get('VNPAYQR') then begin
            PlaylistHdr.Init();
            PlaylistHdr."Playlist No." := 'VNPAYQR';
            PlaylistHdr.Description := 'VNPAY QR Only';
            PlaylistHdr.Insert(true);
        end;


        if RetailImageLink.Get(Format(PlaylistHdr.RecordId), ImageID) then
            RetailImageLink.Delete();

        RetailImageLink.Init();
        RetailImageLink."Record Id" := Format(PlaylistHdr.RecordId);
        RetailImageLink."Image Id" := ImageID;
        RetailImageLink."Link Type" := RetailImageLink."Link Type"::"Image";
        RetailImageLink.Insert(true);


        if RetailImage.Get(ImageID) then
            RetailImage.Delete();


        RetailImage.Init();
        RetailImage.Code := ImageID;
        RetailImage.Insert(true);
        Clear(RetailImage."Image Mediaset");
        TempBlob.CreateInStream(ImageInStream);
        RetailImage."Image Mediaset".ImportStream(ImageInStream, 'VNPAY_QR.png');
        RetailImage.Modify(true);

        ShowVNPAYPanel();

        vnpayStatus_g := 'WAITPAY';
        POSSESSION.SetValue('VNPAYStatus', vnpayStatus_g);
        POSSESSION.SetValue('VNPAYRECEIPT', Format(POSTransaction));
        POSTransaction_g := POSTransaction;
        StartAutoCheck();

        exit(true);
    end;

    procedure ShowVNPAYPanel()
    begin
        POSCtrl.ShowPanelModal('#VNPAY', '#VNPAYQR');
        POSCtrl.Playlist('#VNPAYQR', 'VNPAYQR');
    end;

    local procedure CloseVNPAYPanel()
    begin
        StopAutoCheck();
        POSCtrl.HidePanel('#VNPAY', true);
        POSCtrl.Playlist('#VNPAYQR', '');
        ClearVNPAYSession();
    end;

    local procedure ClearVNPAYSession()
    begin
        vnpayStatus_g := '';
        vnpayAmount_g := 0;
        TenderTypeCode_g := '';
        POSTransaction_g.Init();

        POSSESSION.SetValue('VNPAY_FULL_DATA', '');
        POSSESSION.SetValue('VNPAY_CARD_ENTRY_DONE', '');
        POSSESSION.SetValue('VNPAYStatus', '');
        POSSESSION.SetValue('VNPAYRECEIPT', '');
    end;

    local procedure UniqueRetailImageID(KeyValue: Text): Code[20]
    var
        RetailImage: Record "LSC Retail Image";
        RetValue: Code[20];
        j: Integer;
    begin
        RetValue := CopyStr(KeyValue, 1, 20);
        j := 1;
        while (RetailImage.Get(RetValue) and (j < 20)) do begin
            if StrLen(RetValue) = 20 then begin
                RetValue := 'Y' + CopyStr(RetValue, 1, 19);
                j += 1;
            end else
                RetValue += 'Z';
        end;
        if RetailImage.Get(RetValue) then
            RetValue := Format(Random(500000000));
        exit(RetValue);
    end;

    internal procedure LogText(pheader: Code[20]; ptitle: Text[50]; pText: Text[2048])
    var
        lreccom: Record "LSC Comment";
        nextlineno: Integer;
    begin
        lreccom.SetRange("Linked Record Id Text", pheader);
        if lreccom.FindLast() then
            nextlineno := lreccom."Line No." + 1
        else
            nextlineno := 1;
        lreccom.Init();
        lreccom."Line No." := nextlineno;
        lreccom."Linked Record Id Text" := pheader;
        lreccom.Comment := CopyStr(pText, 1, MaxStrLen(lreccom.Comment));
        lreccom."Comment Category Description" := ptitle;
        lreccom.Insert();
    end;

    local procedure ParseVNPAYDataLine(
        DataLine: Text;
        var ResponseCode: Code[10];
        var DateStr: Text[6];
        var TimeStr: Text[6];
        var TerminalID: Text[20];
        var MerchantCode: Text[20];
        var Invoice: Code[20];
        var PosTerminalID: Code[20];
        var Amount: Decimal)
    var
        Parts: List of [Text];
        Part: Text;
        KeyValue: List of [Text];
    begin
        Clear(ResponseCode);
        Clear(DateStr);
        Clear(TimeStr);
        Clear(TerminalID);
        Clear(MerchantCode);
        Clear(Invoice);
        Clear(PosTerminalID);
        Clear(Amount);

        Parts := DataLine.Split(';');
        foreach Part in Parts do begin
            if Part.Contains(':') then begin
                KeyValue := Part.Split(':');
                if KeyValue.Count() >= 2 then
                    case KeyValue.Get(1) of
                        'RESPONSE_CODE':
                            ResponseCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(ResponseCode));
                        'DATE':
                            DateStr := CopyStr(KeyValue.Get(2), 1, 6);
                        'TIME':
                            TimeStr := CopyStr(KeyValue.Get(2), 1, 6);
                        'TERMINAL_ID':
                            TerminalID := CopyStr(KeyValue.Get(2), 1, MaxStrLen(TerminalID));
                        'MERCHANT_CODE':
                            MerchantCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(MerchantCode));
                        'INVOICE':
                            Invoice := CopyStr(KeyValue.Get(2), 1, MaxStrLen(Invoice));
                        'PosTerminalID':
                            PosTerminalID := CopyStr(KeyValue.Get(2), 1, MaxStrLen(PosTerminalID));
                        'AMOUNT':
                            Evaluate(Amount, KeyValue.Get(2));
                    end;
            end;
        end;
    end;

    local procedure CancelVNPAY()
    var
        ReceiptNo: Code[20];
    begin
        ReceiptNo := POSTransaction_g."Receipt No.";

        if ReceiptNo <> '' then
            VNPAYAPI.CancelPayment(ReceiptNo);

        POSGUI.PosMessage('VNPAY CANCELLED');
        Sleep(800);

        CloseVNPAYPanel();
    end;

    var
        GlobalRec: Record "LSC POS Menu Line";
        POSCtrl: Codeunit "LSC POS Control Interface";
        POSGUI: Codeunit "LSC POS GUI";
        VNPAYAPI: Codeunit "wpVNPayAPIMgt";
        cuPosTrans: Codeunit "LSC POS Transaction";
        POSSESSION: Codeunit "LSC POS Session";
        POSTransaction_g: Record "LSC POS Transaction";
        POSTransLine_g: Record "LSC POS Trans. Line";
        POSTerminal_g: Record "LSC POS Terminal";
        Balance_g: Decimal;
        TenderTypeCode_g: Code[10];
        vnpayStatus_g: Code[20];
        vnpayType_g: Code[20];
        vnpayAmount_g: Decimal;
        IsWaitingForAutoCheck: Boolean;
        AutoCheckCount: Integer;
        LastAutoCheckTime: DateTime;

}