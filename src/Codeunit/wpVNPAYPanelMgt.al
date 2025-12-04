/* codeunit 70008 "wpVNPAYPanelMgt"
{
    SingleInstance = true;
    TableNo = "LSC POS Menu Line";

    trigger OnRun()
    begin
        if IsPolling then
            CheckPollingTimer();

        if Rec."Pos Event Type" = Rec."Pos Event Type"::PANELCLOSED then begin
            StopPolling();
            exit;
        end;

        Rec.Processed := true;
        GlobalRec := Rec;

        case GlobalRec."Pos Event Type" of
            GlobalRec."Pos Event Type"::POSCOMMAND,
            GlobalRec."Pos Event Type"::BUTTONPRESS:
                EventType_g := 'BUTTONPRESS';
            GlobalRec."Pos Event Type"::QUERYPANELCLOSE:
                begin
                    if not ClosingFromEsc_g then begin
                        ClosingFromEsc_g := true;
                        StopPolling();
                    end;
                    exit;
                end;
            GlobalRec."Pos Event Type"::PANELCLOSED:
                begin
                    StopPolling();
                    exit;
                end;
            else
                ClosingFromEsc_g := true;
        end;

        ActivePanelID := LastPosEvent.ActivePanelID;

        if ActivePanelID = '#VNPAY' then
            HandleVNPAYPanel();

        Rec := GlobalRec;
    end;

    local procedure HandleVNPAYPanel()
    begin
        if EventType_g = 'BUTTONPRESS' then
            case GlobalRec.Parameter of
                'CHECK':
                    ManualCheckStatus();
                'OK':
                    CloseVNPAYPanel();
                else
                    GlobalRec.Processed := false;
            end
        else
            GlobalRec.Processed := false;
    end;

    local procedure ManualCheckStatus()
    var
        StatusCode: Integer;
        DataLine: Text;
        StatusOK: Boolean;
    begin
        if CurrentReceiptNo = '' then begin
            Message('Không tìm thấy mã giao dịch');
            exit;
        end;

        StatusOK := VNPAYAPI.CheckPaymentStatus(CurrentReceiptNo, StatusCode, DataLine);

        if not StatusOK then begin
            Message('Không thể kiểm tra trạng thái thanh toán.');
            exit;
        end;

        case StatusCode of
            200:
                begin
                    ProcessSuccessfulPayment(DataLine);
                    VNPAYAPI.ConsoleLogVNPAYSuccess(CurrentReceiptNo, DataLine);
                end;
            201:
                Message('Trạng thái: ĐANG XỬ LÝ\Vui lòng đợi khách hàng quét mã QR');
            204:
                begin
                    Message('Thanh toán thất bại hoặc hết hạn');
                    CloseVNPAYPanel();
                end;
            else
                Message('Trạng thái không xác định: %1', StatusCode);
        end;
    end;

    local procedure StartPolling()
    begin
        IsPolling := true;
        PollingCount := 0;
        LastPollingTime := CurrentDateTime - 3000;
    end;

    local procedure StopPolling()
    begin
        IsPolling := false;
        PollingCount := 0;
    end;

    local procedure CheckPollingTimer()
    var
        Elapsed: Integer;
    begin
        if not IsPolling then exit;

        Elapsed := (CurrentDateTime - LastPollingTime) div 1000;
        if Elapsed >= 5 then begin
            LastPollingTime := CurrentDateTime;
            PollingCount += 1;
            if PollingCount > 60 then begin
                Message('Hết thời gian chờ thanh toán');
                CloseVNPAYPanel();
                StopPolling();
                exit;
            end;
            PollPaymentStatus();
        end;
    end;

    local procedure PollPaymentStatus()
    var
        StatusCode: Integer;
        DataLine: Text;
        StatusOK: Boolean;
    begin
        if CurrentReceiptNo = '' then begin
            StopPolling();
            exit;
        end;

        StatusOK := VNPAYAPI.CheckPaymentStatus(CurrentReceiptNo, StatusCode, DataLine);

        if not StatusOK then exit;

        case StatusCode of
            200:
                begin
                    StopPolling();
                    ProcessSuccessfulPayment(DataLine);
                    VNPAYAPI.ConsoleLogVNPAYSuccess(CurrentReceiptNo, DataLine);
                end;
            201:
                ;
            204:
                begin
                    Message('Thanh toán thất bại hoặc hết hạn');
                    CloseVNPAYPanel();
                    StopPolling();
                end;
            else begin
                Message('Thanh toán thất bại');
                CloseVNPAYPanel();
                StopPolling();
            end;
        end;
    end;

    local procedure ProcessSuccessfulPayment(DataLine: Text)
    var
        POSTransaction: Record "LSC POS Transaction";
        POSTransLine: Record "LSC POS Trans. Line";
        LRecCE: Record "LSC POS Card Entry";
        nextEntryNo: Integer;
        APP, ResponseCode, VNPDate, VNPTime, TerminalID, MerchantCode, Invoice, PosTerminalID, VNPAmount : Text;
        AmountDecimal: Decimal;
    begin
        if not POSTransaction.Get(CurrentReceiptNo) then begin
            Message('Không tìm thấy giao dịch');
            CloseVNPAYPanel();
            exit;
        end;

        VNPAYAPI.ParseVNPAYData(DataLine, APP, ResponseCode, VNPDate, VNPTime, TerminalID, MerchantCode, Invoice, PosTerminalID, VNPAmount);

        if ResponseCode <> '00' then begin
            POSGUI.PosMessage('Thanh toán thất bại!');
            CloseVNPAYPanel();
            exit;
        end;

        if not Evaluate(AmountDecimal, VNPAmount) then begin
            POSGUI.PosMessage('Lỗi: Không thể đọc số tiền');
            CloseVNPAYPanel();
            exit;
        end;

        if Abs(AmountDecimal - CurrentAmount) > 0.01 then begin
            POSGUI.PosMessage(StrSubstNo('Lỗi: Số tiền không khớp. Mong đợi %1, nhận %2', CurrentAmount, AmountDecimal));
            CloseVNPAYPanel();
            exit;
        end;


        POSTransLine.Reset();
        POSTransLine.SetRange("Receipt No.", CurrentReceiptNo);
        if not POSTransLine.FindLast() then begin
            POSGUI.PosMessage('Không tìm thấy dòng thanh toán');
            CloseVNPAYPanel();
            exit;
        end;


        LRecCE.Reset();
        LRecCE.SetRange("Store No.", POSTransaction."Store No.");
        LRecCE.SetRange("POS Terminal No.", POSTransaction."POS Terminal No.");
        if LRecCE.FindLast() then
            nextEntryNo := LRecCE."Entry No." + 1
        else
            nextEntryNo := 1;

        LRecCE.Init();
        LRecCE."Store No." := POSTransaction."Store No.";
        LRecCE."POS Terminal No." := POSTransaction."POS Terminal No.";
        LRecCE."Entry No." := nextEntryNo;
        LRecCE."Line No." := POSTransLine."Line No.";
        LRecCE."Receipt No." := CurrentReceiptNo;
        LRecCE."Tender Type" := '86';
        LRecCE."Transaction Type" := LRecCE."Transaction Type"::Sale;
        LRecCE."Card Number" := 'VNPAY';
        LRecCE."Card Type" := 'VNPAY';
        LRecCE."Card Type Name" := 'VNPAY QR Payment';
        LRecCE."Res.code" := ResponseCode;
        LRecCE."EFT Merchant No." := MerchantCode;
        LRecCE."EFT Trans. Date" := VNPDate;
        LRecCE."EFT Trans. Time" := VNPTime;
        LRecCE.Amount := AmountDecimal;
        LRecCE."EFT Transaction ID" := Invoice;
        LRecCE."EFT Terminal ID" := TerminalID;
        LRecCE."Extra Data" := PosTerminalID;
        LRecCE.Date := Today;
        LRecCE.Time := Time;
        LRecCE."Authorisation Ok" := true;
        LRecCE.Insert(true);

        Commit();

        POSGUI.PosMessage('THANH TOÁN THÀNH CÔNG!');
        Sleep(1500);

        CloseVNPAYPanel();

    end;



    local procedure CloseVNPAYPanel()
    begin
        POSCtrl.HidePanel('#VNPAY', true);
        POSCtrl.Playlist('#VNPAYQR', '');
        ClearVNPAYSession();
    end;

    local procedure ClearVNPAYSession()
    begin
        CurrentReceiptNo := '';
        CurrentAmount := 0;
        IsPolling := false;
        PollingCount := 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnAfterTenderKeyPressedEx', '', false, false)]
    local procedure OnAfterTenderKeyPressedEx(var POSTransaction: Record "LSC POS Transaction"; var POSTransLine: Record "LSC POS Trans. Line"; var CurrInput: Text; var TenderTypeCode: Code[10]; var TenderAmountText: Text; var IsHandled: Boolean)
    var
        TempBlob: Codeunit "Temp Blob";
        RetailImage: Record "LSC Retail Image";
        RetailImageLink: Record "LSC Retail Image Link";
        PlaylistHdr: Record "LSC POS Media Playlist Header";
        ImageInStream: InStream;
        QRContent: Text;
        Amount: Decimal;
        CheckStatusUrl: Text;
        ImageID: Code[20];
    begin
        if TenderTypeCode <> '86' then exit;

        Amount := Round(POSTransaction."Gross Amount" - POSTransaction.Payment, 0.01);
        if Amount <= 0 then Amount := POSTransaction."Gross Amount";



        POSCtrl.HidePanel('', true);

        CurrentReceiptNo := POSTransaction."Receipt No.";
        CurrentAmount := Amount;

        QRContent := VNPAYAPI.GetPaymentQR(CurrentReceiptNo, Amount, TempBlob, CheckStatusUrl);
        if QRContent = '' then begin
            Message('Không kết nối được VNPAY');
            IsHandled := false;
            exit;
        end;

        if not TempBlob.HasValue() then
            SwissQRCodeHelper.GenerateQRCodeImage(QRContent, TempBlob);

        if not PlaylistHdr.Get('VNPAYQR') then begin
            PlaylistHdr.Init();
            PlaylistHdr."Playlist No." := 'VNPAYQR';
            PlaylistHdr.Description := 'VNPAY QR Only';
            PlaylistHdr.Insert(true);
        end;

        ImageID := 'VNPQR' + CopyStr(CurrentReceiptNo, 1, 15);

        if not RetailImageLink.Get(Format(PlaylistHdr.RecordId), ImageID) then begin
            RetailImageLink.Init();
            RetailImageLink."Record Id" := Format(PlaylistHdr.RecordId);
            RetailImageLink."Image Id" := ImageID;
            RetailImageLink."Link Type" := RetailImageLink."Link Type"::"Image";
            RetailImageLink.Insert(true);
        end;

        if not RetailImage.Get(ImageID) then begin
            RetailImage.Init();
            RetailImage.Code := ImageID;
            RetailImage.Insert(true);
        end;

        Clear(RetailImage."Image Mediaset");
        TempBlob.CreateInStream(ImageInStream);
        RetailImage."Image Mediaset".ImportStream(ImageInStream, 'VNPAY_QR.png');
        RetailImage.Modify(true);

        // Show panel immediately so button appears responsive
        POSCtrl.Playlist('#VNPAYQR', 'VNPAYQR');
        POSCtrl.ShowPanel('#VNPAY');
        StartPolling();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnAfterInsertPaymentLine', '', false, false)]
    local procedure OnAfterInsertPaymentLine(var POSTransaction: Record "LSC POS Transaction"; var POSTransLine: Record "LSC POS Trans. Line"; var CurrInput: Text; var TenderTypeCode: Code[10]; var SkipCommit: Boolean)
    begin
        if TenderTypeCode <> '86' then exit;
        if POSTransaction."Receipt No." <> CurrentReceiptNo then exit;

        POSCtrl.Playlist('#VNPAYQR', 'VNPAYQR');
        POSCtrl.ShowPanel('#VNPAY');
        StartPolling();

        SkipCommit := true;
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
        lreccom.Comment := pText;
        lreccom."Comment Category Description" := ptitle;
        lreccom.Insert();
    end;

    var
        ActivePanelID: Code[20];
        CurrentReceiptNo: Code[20];
        CurrentAmount: Decimal;
        IsPolling: Boolean;
        PollingCount: Integer;
        LastPollingTime: DateTime;
        GlobalRec: Record "LSC POS Menu Line";
        POSCtrl: Codeunit "LSC POS Control Interface";
        POSGUI: Codeunit "LSC POS GUI";
        VNPAYAPI: Codeunit "wpVNPayAPIMgt";
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
        LastPosEvent: Codeunit "LSC POS Control Event";
        EventType_g: Code[30];
        ClosingFromEsc_g: Boolean;
        cuPosTrans: Codeunit "LSC POS Transaction";
}

 */
codeunit 70008 "wpVNPAYPanelMgt"
{
    SingleInstance = true;
    TableNo = "LSC POS Menu Line";

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"LSC POS Transaction Events", 'OnAfterInsertPaymentLine', '', false, false)]
    local procedure OnAfterInsertPaymentLine(var POSTransaction: Record "LSC POS Transaction"; var POSTransLine: Record "LSC POS Trans. Line"; var CurrInput: Text; var TenderTypeCode: Code[10]; var SkipCommit: Boolean)
    var
        POSTerminal: Record "LSC POS Terminal";
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
        PlaylistHdr: Record "LSC POS Media Playlist Header";
        QRUrl: Text;
        Amount: Decimal;
        RetailImageLink: Record "LSC Retail Image Link";
        RetailImage: Record "LSC Retail Image";
        RecID: RecordID;
        TempBLOB: Codeunit "Temp Blob";
        Client: HttpClient;
        Response: HttpResponseMessage;
        ImageInStream: InStream;
        PlaylistID: Code[20];
        CheckStatusUrl: Text;
    begin



        clear(POSTerminal);
        /*  POSTerminal.setrange("Store No.", POSTransaction."Store No.");
         POSTerminal.setrange("No.", POSTransaction."POS Terminal No.");
         if POSTerminal.FindFirst() then begin
             if POSTerminal."Enable VNPay Integration" = false then
                 SkipCommit := true;
             exit;
         end; */
        IF POSTransaction."Sale Is Return Sale" then
            exit;
        POSSESSION.SetValue('RECEIPTNO', POSTransaction."Receipt No.");
        Amount := POSTransaction."Gross Amount";
        //QRUrl := VNPAYAPI.GetPaymentQR(POSTransaction."Receipt No.", Amount); // or a test URL

        QRUrl := VNPAYAPI.GetPaymentQR(POSTransaction."Receipt No.", Amount, TempBlob, CheckStatusUrl);
        if not SwissQRCodeHelper.GenerateQRCodeImage(QRUrl, TempBlob) then
            Error('Failed to generate VNPay QR');
        PlaylistID := 'VNPAY_' + CopyStr(POSTransaction."Receipt No.", 8, 12);
        if not PlaylistHdr.Get(PlaylistID) then begin
            PlaylistHdr.Init();
            PlaylistHdr."Playlist No." := PlaylistID;
            PlaylistHdr.Description := Format(PlaylistID);
            PlaylistHdr.Insert();
        end;
        RetailImageLink.Init();
        RetailImageLink.Validate("Record Id", format(PlaylistHdr.RecordId)); // link to this transaction
        RetailImageLink."Image Id" := UniqueRetailImageID(RetailImageLink.KeyValue);
        RetailImageLink."Link Type" := RetailImageLink."Link Type"::"Image";
        RetailImageLink.Validate("Image Description", POSTransaction."Receipt No.");
        if not RetailImageLink.Insert() then
            RetailImageLink.Modify();
        if not RetailImage.Get(RetailImageLink."Image Id") then begin
            RetailImage.Init();
            RetailImage.Code := RetailImageLink."Image Id";
        end;
        TempBlob.CreateInStream(ImageInStream);
        RetailImage."Image Mediaset".ImportStream(ImageInStream, '');
        RetailImage.Insert(true);

        ShowVNPAYPanel(PlaylistID, SkipCommit);

    end;

    local procedure InsertTenderAmount(var POSTransaction: Record "LSC POS Transaction"; var POSTransLine: Record "LSC POS Trans. Line")
    begin
        // Placeholder for future logic if needed
    end;

    procedure ShowVNPAYPanel(var PlaylistID: Code[20]; var SkipCommit: Boolean)
    begin
        SkipCommit := false;

        POSCtrl.ShowPanelModal('#VNPAY', '#VNPAYQR');
        POSCtrl.Playlist('#VNPAYQR', Format(PlaylistID));
        // StartPolling();
    end;

    local procedure CloseVNPAYPanel()
    begin
        POSCtrl.HidePanel('#VNPAY', true);
        POSCtrl.Playlist('#VNPAYQR', '');
        //  ClearVNPAYSession();
    end;

    local procedure UniqueRetailImageID(KeyValue: text): Code[20]
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
                j := j + 1;
            end;
            if StrLen(RetValue) < 20 then
                RetValue := RetValue + 'Z';
        end;
        if RetailImage.Get(RetValue) then
            RetValue := format(Random(500000000));
        exit(RetValue);
    end;

    var
        ActivePanelID: Code[20];
        CurrentReceiptNo: Code[20];
        CurrentAmount: Decimal;
        IsPolling: Boolean;
        PollingCount: Integer;
        LastPollingTime: DateTime;
        GlobalRec: Record "LSC POS Menu Line";
        POSCtrl: Codeunit "LSC POS Control Interface";
        POSGUI: Codeunit "LSC POS GUI";
        VNPAYAPI: Codeunit "wpVNPayAPIMgt";
        SwissQRCodeHelper: Codeunit "Swiss QR Code Helper";
        LastPosEvent: Codeunit "LSC POS Control Event";
        EventType_g: Code[30];
        ClosingFromEsc_g: Boolean;
        cuPosTrans: Codeunit "LSC POS Transaction";
        POSSESSION: Codeunit "LSC POS Session";

}