codeunit 70015 "wpVCBPanelMgt"
{
    SingleInstance = true;
    TableNo = "LSC POS Menu Line";

    trigger OnRun()
    begin
        Rec.Processed := true;
        GlobalRec := Rec;

        if IsWaitingForAutoCheck then
            CheckAutoCheckTimer();

        if GlobalRec."Pos Event Type" = GlobalRec."Pos Event Type"::BUTTONPRESS then begin
            if GlobalRec.Parameter = 'CHECK' then begin
                if vcbStatus_g = 'PAID' then exit;
                ManualCheckStatus();
            end else
                if GlobalRec.Parameter = 'OK' then
                    CancelVCB()
                else
                    GlobalRec.Processed := false;
        end else
            GlobalRec.Processed := false;
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
        FirstCheck: Integer;
        IntervalCheck: Integer;
        MaxRetries: Integer;
        Store: Record "LSC Store";
        POSTerminal: Record "LSC POS Terminal";
    begin
        if not IsWaitingForAutoCheck then exit;

        if not POSTerminal.Get(POSSESSION.TerminalNo) then
            Error('POS Terminal not found.');
        if not Store.Get(POSTerminal."Store No.") then
            Error('Store not found.');

        FirstCheck := Store."VCB First Check Delay Sec";
        IntervalCheck := Store."VCB Check Interval Sec";
        MaxRetries := Store."VCB Max Retries";

        if FirstCheck = 0 then Error('VCB First Check Delay is missing in Store setup.');
        if IntervalCheck = 0 then Error('VCB Check Interval is missing in Store setup.');
        if MaxRetries = 0 then MaxRetries := 90;

        Elapsed := (CurrentDateTime - LastAutoCheckTime) div 1000;

        if AutoCheckCount = 0 then
            WaitTime := FirstCheck
        else
            WaitTime := IntervalCheck;

        if Elapsed >= WaitTime then begin
            LastAutoCheckTime := CurrentDateTime;
            AutoCheckCount += 1;

            if AutoCheckCount > MaxRetries then begin
                if vcbStatus_g in ['PAID', 'FAILED', 'CANCELLED', 'EXPIRED', ''] then begin
                    VCBAPI.LogText(POSTransaction_g."Receipt No.",
                        'VCB_AUTO_CHECK_TIMEOUT',
                        StrSubstNo('Stopping at status=%1, Count=%2', vcbStatus_g, AutoCheckCount));
                    StopAutoCheck();
                    exit;
                end else begin
                    if (AutoCheckCount mod 30) = 0 then
                        VCBAPI.LogText(POSTransaction_g."Receipt No.",
                            'VCB_AUTO_CHECK_EXTENDED',
                            StrSubstNo('Still checking, Count=%1, Status=%2', AutoCheckCount, vcbStatus_g));
                end;
            end;

            PerformAutoCheck();
        end;
    end;

    local procedure PerformAutoCheck()
    var
        StatusCode: Code[10];
        FullDataLine: Text;
        TenderTypeCode: Code[10];
    begin
        if POSTransaction_g."Receipt No." = '' then begin
            StopAutoCheck();
            exit;
        end;

        StatusCode := VCBAPI.CheckPaymentStatus(POSTransaction_g."Receipt No.", FullDataLine);

        case StatusCode of
            '200':
                begin
                    POSSESSION.SetValue('VCB_FULL_DATA', FullDataLine);

                    TenderTypeCode := POSSESSION.GetValue('VCBTENDER');
                    if TenderTypeCode = '' then
                        TenderTypeCode := GetVCBTenderTypeCode();

                    if POSSESSION.GetValue('VCB_CARD_ENTRY_DONE') <> 'YES' then
                        cuPosTrans.TenderKeyPressedEx(TenderTypeCode, Format(vcbAmount_g));

                    POSSESSION.SetValue('VCBTENDER', TenderTypeCode);
                    vcbStatus_g := 'PAID';
                    POSSESSION.SetValue('VCBStatus', vcbStatus_g);

                    StopAutoCheck();
                    Sleep(1500);
                    CloseVCBPanel();
                end;
            '201':
                ; // Still processing
            else begin
                StopAutoCheck();
                POSGUI.PosMessage('VCB PAYMENT FAILED OR EXPIRED');
                CloseVCBPanel();
            end;
        end;
    end;

    // ── POS Events ────────────────────────────────────────────────────────────

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnBeforeInit', '', false, false)]
    local procedure OnBeforeInit(var POSTransaction: Record "LSC POS Transaction")
    begin
        vcbStatus_g := '';
        vcbAmount_g := 0;
        TenderTypeCode_g := '';
        IsWaitingForAutoCheck := false;
        AutoCheckCount := 0;
        POSSESSION.SetValue('VCBRECEIPT', '');
        POSSESSION.SetValue('VCBBALANCE', '');
        POSSESSION.SetValue('VCBTENDER', '');
        POSSESSION.SetValue('VCBStatus', '');
        POSSESSION.SetValue('VCBAmount', '');
        POSTransaction_g := POSTransaction;
        if POSTerminal_g.Get(POSSESSION.TerminalNo) then;
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
    var
        VCBTenderCode: Code[10];
    begin
        VCBTenderCode := GetVCBTenderTypeCode();
        if VCBTenderCode = '' then exit;
        if TenderTypeCode <> VCBTenderCode then exit;

        if POSSESSION.GetValue('VCBRECEIPT') <> POSTransaction."Receipt No." then begin
            vcbStatus_g := '';
            POSSESSION.SetValue('VCBStatus', '');
            POSSESSION.SetValue('VCBRECEIPT', '');
        end else
            vcbStatus_g := POSSESSION.GetValue('VCBStatus');

        if vcbStatus_g = '' then begin
            if InsertTenderAmount(POSTransaction, PaymentAmount) then begin
                TenderTypeCode_g := TenderTypeCode;
                vcbAmount_g := PaymentAmount;
                POSSESSION.SetValue('VCBRECEIPT', POSTransaction."Receipt No.");
                isHandled := true;
            end;
        end else
            isHandled := false;
    end;

    local procedure InsertTenderAmount(var POSTransaction: Record "LSC POS Transaction"; var TransAmount: Decimal): Boolean
    var
        POSTerminal: Record "LSC POS Terminal";
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
        PlaylistHdr: Record "LSC POS Media Playlist Header";
        RetailImageLink: Record "LSC Retail Image Link";
        RetailImage: Record "LSC Retail Image";
        TempBLOB: Codeunit "Temp Blob";
        ImageInStream: InStream;
        CheckStatusUrl: Text;
        UserID: Code[20];
        ImageID: Code[20];
        ImageFileName: Text[250];
        Counter: Integer;
        Store: Record "LSC Store";
        QRUrl: Text;
    begin
        if POSTransaction."Sale Is Return Sale" then exit;

        if not POSTerminal.Get(POSTransaction."POS Terminal No.") then
            Error('POS Terminal not found.');
        if not Store.Get(POSTerminal."Store No.") then
            Error('Store not found.');
        if not Store."Enable VCB Integration" then
            Error('VCB is not enabled on this store.');

        POSSESSION.SetValue('RECEIPTNO', POSTransaction."Receipt No.");

        if POSTerminal_g."No." <> '' then
            UserID := POSTerminal_g."No."
        else
            UserID := POSSESSION.TerminalNo;

        if TransAmount < 1000 then
            Error('Minimum VCB payment amount is 1,000 VND.');

        // Get QR payload from VCB via our .NET API
        QRUrl := VCBAPI.GetPaymentQR(
            POSTransaction."Receipt No.", TransAmount, UserID, TempBlob, CheckStatusUrl);

        // Generate QR image
        if not SwissQRCodeHelper.GenerateQRCodeImage(QRUrl, TempBlob) then
            Error('Failed to generate VCB QR image');

        // ── Store QR image in LSC Retail Image (same pattern as VNPAY) ───────
        ImageID := 'VCB';
        Counter := 0;
        if Evaluate(Counter, POSSESSION.GetValue('VCB_IMAGE_COUNTER')) then
            Counter += 1
        else
            Counter := 1;
        POSSESSION.SetValue('VCB_IMAGE_COUNTER', Format(Counter));
        ImageFileName := StrSubstNo('VCB_QR_%1.png', Counter);

        if not PlaylistHdr.Get('VCBQR') then begin
            PlaylistHdr.Init();
            PlaylistHdr."Playlist No." := 'VCBQR';
            PlaylistHdr.Description := 'VCB QR Only';
            PlaylistHdr.Insert(true);
        end;

        RetailImageLink.Reset();
        RetailImageLink.SetRange("Record Id", Format(PlaylistHdr.RecordId));
        if RetailImageLink.FindSet() then
            RetailImageLink.DeleteAll();

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
        RetailImage."Image Mediaset".ImportStream(ImageInStream, ImageFileName);
        RetailImage.Modify(true);
        Commit();

        ShowVCBPanel();
        StartAutoCheck();

        vcbStatus_g := 'WAITPAY';
        POSSESSION.SetValue('VCBStatus', vcbStatus_g);
        POSSESSION.SetValue('VCBRECEIPT', POSTransaction."Receipt No.");
        POSTransaction_g := POSTransaction;

        exit(true);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnAfterInsertPaymentLine', '', false, false)]
    local procedure OnAfterInsertPaymentLine_VCB(
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
        TransactionCode: Code[20];
        BankCode: Text[20];
        ApprovalCode: Text[20];
        CardFirst6: Text[10];
        CardLast4: Text[10];
        RealAmount: Decimal;
        PartnerTransCode: Text[20];
        VCBTenderCode: Code[10];
    begin
        VCBTenderCode := GetVCBTenderTypeCode();
        if VCBTenderCode = '' then exit;
        if TenderTypeCode <> VCBTenderCode then exit;
        if POSTransLine."Entry Type" <> POSTransLine."Entry Type"::Payment then exit;
        if POSSESSION.GetValue('VCB_CARD_ENTRY_DONE') = 'YES' then exit;

        FullDataLine := POSSESSION.GetValue('VCB_FULL_DATA');
        if FullDataLine = '' then
            FullDataLine := StrSubstNo('APP:VCB;RESPONSE_CODE:00;INVOICE:%1;AMOUNT:%2;',
                POSTransaction."Receipt No.", Format(POSTransLine.Amount));

        // Reuse same parser as VNPAY — data line format is identical
        ParseVCBDataLine(
            FullDataLine,
            ResponseCode, DateStr, TimeStr,
            TerminalID, MerchantCode, Invoice, PosTerminalID,
            Amount, TransactionCode,
            BankCode, ApprovalCode,
            CardFirst6, CardLast4,
            RealAmount, PartnerTransCode);

        VCBAPI.LogText(
            POSTransaction."Receipt No.",
            'VCB Parsed Data',
            StrSubstNo('TransCode:%1;Bank:%2;Approval:%3;RealAmt:%4;PartnerTrans:%5',
                TransactionCode, BankCode, ApprovalCode, RealAmount, PartnerTransCode));

        // ── Write Card Entry ─────────────────────────────────────────────────
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
        CardEntry."Tender Type" := VCBTenderCode;
        CardEntry."Transaction Type" := CardEntry."Transaction Type"::Sale;
        CardEntry."Card Number" := 'VCB_QR';
        CardEntry."Card Type" := 'VCB';
        CardEntry."Res.code" := ResponseCode;

        if ApprovalCode <> '' then
            CardEntry."EFT Auth.code" := ApprovalCode
        else
            CardEntry."EFT Auth.code" := 'VCB';

        CardEntry."EFT Trans. No." := TransactionCode;
        CardEntry."EFT Merchant No." := MerchantCode;
        CardEntry."EFT Trans. Date" := DateStr;
        CardEntry."EFT Trans. Time" := TimeStr;

        if RealAmount > 0 then
            CardEntry.Amount := RealAmount
        else
            CardEntry.Amount := Amount;

        CardEntry."EFT Transaction ID" := Invoice;
        CardEntry."EFT Currency" := 'VND';
        CardEntry."EFT Terminal ID" := TerminalID;
        CardEntry."Auth. Source Code" := 'VCB';
        CardEntry.Date := Today;
        CardEntry.Time := Time;
        CardEntry."Authorisation Ok" := (ResponseCode = '00');
        CardEntry.Insert(true);

        VCBAPI.LogText(POSTransaction."Receipt No.", 'VCB Card Entry Created',
            StrSubstNo('EntryNo:%1', NextEntryNo));

        POSSESSION.SetValue('VCB_CARD_ENTRY_DONE', 'YES');
        POSSESSION.SetValue('VCBAmount', '');
    end;

    // ── Manual check (CHECK button on panel) ─────────────────────────────────

    local procedure ManualCheckStatus()
    var
        StatusCode: Code[10];
        FullDataLine: Text;
    begin
        StatusCode := VCBAPI.CheckPaymentStatus(POSTransaction_g."Receipt No.", FullDataLine);

        case StatusCode of
            '200':
                begin
                    POSSESSION.SetValue('VCB_FULL_DATA', FullDataLine);
                    POSGUI.PosMessage('VCB PAYMENT SUCCESSFUL');
                    Sleep(1000);
                end;
            '201':
                begin
                    POSGUI.PosMessage('VCB TRANSACTION STILL PROCESSING');
                    Sleep(2000);
                end;
            else begin
                POSGUI.PosMessage('VCB PAYMENT FAILED OR EXPIRED');
                Sleep(3000);
                CloseVCBPanel();
            end;
        end;
    end;

    // ── Panel show/hide ───────────────────────────────────────────────────────

    procedure ShowVCBPanel()
    begin
        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::Pos);
        POSCtrl.ShowPanelModal('#VCB', '#VCBQR');

        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::DualDisplay);
        POSCtrl.ShowPanelModal('#VCB', '#VCBQR');

        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::Pos);
    end;

    local procedure CloseVCBPanel()
    var
        RetailImage: Record "LSC Retail Image";
        RetailImageLink: Record "LSC Retail Image Link";
        PlaylistHdr: Record "LSC POS Media Playlist Header";
    begin
        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::Pos);
        POSCtrl.HidePanel('#VCB', true);

        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::DualDisplay);
        POSCtrl.HidePanel('#VCB', true);

        POSCtrl.Playlist('#VCBQR', '');
        POSCtrl.RefreshInterfaceProfile('');
        POSCtrl.Playlist('#VCBQR', 'VCBQR');

        if PlaylistHdr.Get('VCBQR') then begin
            RetailImageLink.SetRange("Record Id", Format(PlaylistHdr.RecordId));
            RetailImageLink.DeleteAll(true);
        end;

        if RetailImage.Get('VCB') then begin
            Clear(RetailImage."Image Mediaset");
            RetailImage.Modify(true);
            RetailImage.Delete(false);
        end;

        Commit();
        POSCtrl.SetClientTypeEnum("LSC POS Client Type"::Pos);
        ClearVCBSession();
    end;

    local procedure CancelVCB()
    var
        ReceiptNo: Code[20];
    begin
        ReceiptNo := POSTransaction_g."Receipt No.";
        if ReceiptNo <> '' then
            VCBAPI.CancelPayment(ReceiptNo);

        POSGUI.PosMessage('VCB CANCELLED');
        Sleep(800);
        CloseVCBPanel();
    end;

    local procedure ClearVCBSession()
    begin
        vcbStatus_g := '';
        TenderTypeCode_g := '';
        POSTransaction_g.Init();
        POSSESSION.SetValue('VCB_FULL_DATA', '');
        POSSESSION.SetValue('VCB_CARD_ENTRY_DONE', '');
        POSSESSION.SetValue('VCBStatus', '');
        POSSESSION.SetValue('VCBRECEIPT', '');
        POSSESSION.SetValue('VCB_STATUS_LOGGED', '');
    end;

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Read VCB tender type code from Store setup.
    /// Returns '' if not configured, which causes all event subscribers to exit safely.
    /// </summary>
    local procedure GetVCBTenderTypeCode(): Code[10]
    var
        POSTerminal: Record "LSC POS Terminal";
        Store: Record "LSC Store";
    begin
        if not POSTerminal.Get(POSSESSION.TerminalNo) then exit('');
        if not Store.Get(POSTerminal."Store No.") then exit('');
        exit(Store."VCB Tender Type Code");
    end;

    /// <summary>
    /// Parse the semicolon-delimited data line returned by /api/vcb/status.
    /// Same format as VNPAY data line — APP:VCB;RESPONSE_CODE:00;DATE:...
    /// Extended with DEBIT_ACCT and DEBIT_NAME fields.
    /// </summary>
    local procedure ParseVCBDataLine(
        DataLine: Text;
        var ResponseCode: Code[10];
        var DateStr: Text[6];
        var TimeStr: Text[6];
        var TerminalID: Text[20];
        var MerchantCode: Text[20];
        var Invoice: Code[20];
        var PosTerminalID: Code[20];
        var Amount: Decimal;
        var TransactionCode: Code[20];
        var BankCode: Text[20];
        var ApprovalCode: Text[20];
        var CardFirst6: Text[10];
        var CardLast4: Text[10];
        var RealAmount: Decimal;
        var PartnerTransCode: Text[20])
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
        Clear(TransactionCode);
        Clear(BankCode);
        Clear(ApprovalCode);
        Clear(CardFirst6);
        Clear(CardLast4);
        Clear(RealAmount);
        Clear(PartnerTransCode);

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
                        'TRANSACTION_CODE':
                            TransactionCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(TransactionCode));
                        'BANK_CODE':
                            BankCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(BankCode));
                        'APPROVAL_CODE':
                            ApprovalCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(ApprovalCode));
                        'CARD_FIRST6':
                            CardFirst6 := CopyStr(KeyValue.Get(2), 1, MaxStrLen(CardFirst6));
                        'CARD_LAST4':
                            CardLast4 := CopyStr(KeyValue.Get(2), 1, MaxStrLen(CardLast4));
                        'REAL_AMOUNT':
                            Evaluate(RealAmount, KeyValue.Get(2));
                        'PARTNER_TRANS_CODE':
                            PartnerTransCode := CopyStr(KeyValue.Get(2), 1, MaxStrLen(PartnerTransCode));
                        // VCB-specific extra fields — stored in session for receipt printing
                        'DEBIT_ACCT':
                            POSSESSION.SetValue('VCB_DEBIT_ACCT', CopyStr(KeyValue.Get(2), 1, 50));
                        'DEBIT_NAME':
                            POSSESSION.SetValue('VCB_DEBIT_NAME', CopyStr(KeyValue.Get(2), 1, 70));
                    end;
            end;
        end;
    end;

    // ── Variables ─────────────────────────────────────────────────────────────

    var
        GlobalRec: Record "LSC POS Menu Line";
        POSCtrl: Codeunit "LSC POS Control Interface";
        POSGUI: Codeunit "LSC POS GUI";
        VCBAPI: Codeunit "wpVCBAPIMgt";
        cuPosTrans: Codeunit "LSC POS Transaction";
        POSSESSION: Codeunit "LSC POS Session";
        POSTransaction_g: Record "LSC POS Transaction";
        POSTerminal_g: Record "LSC POS Terminal";
        TenderTypeCode_g: Code[10];
        vcbStatus_g: Code[20];
        vcbAmount_g: Decimal;
        IsWaitingForAutoCheck: Boolean;
        AutoCheckCount: Integer;
        LastAutoCheckTime: DateTime;
        TempBlob: Codeunit "Temp Blob";
}
