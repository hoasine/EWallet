tableextension 70010 VNPayPOSTerminal extends "LSC POS Terminal"
{
    fields
    {
        field(72107; "Enable VNPay Integration"; Boolean)
        {
            Caption = 'Enable VNPay Integration';
            DataClassification = ToBeClassified;
        }
        field(72108; "VNPAY Payment Service URL"; Text[30])
        {
            Caption = 'VCB Payment Service URL';
            DataClassification = ToBeClassified;
        }
        field(72110; "VNPAY Terminal ID"; Text[20])
        {
            Caption = 'VNPAY Terminal ID';
            DataClassification = ToBeClassified;
        }
        field(72111; "VNPAY Merchant ID"; Text[20])
        {
            Caption = 'VNPAY Merchant ID';
            DataClassification = ToBeClassified;
        }
        field(72112; "VNPay Time Out"; Integer)
        {
            Caption = 'VNPay Time Out';
            DataClassification = ToBeClassified;
        }
        field(72113; "VNPay Max Retries"; Integer)
        {
            Caption = 'VNPay Max Retries';
            DataClassification = ToBeClassified;
        }
        field(72114; "VNPAY First Check Delay Sec"; Integer)
        {
            Caption = 'VNPAY First Check Delay Sec';
            DataClassification = ToBeClassified;
        }
        field(72115; "VNPAY Check Interval Sec"; Integer)
        {
            Caption = 'VNPAY Check Interval Sec';
            DataClassification = ToBeClassified;
        }
    }
}
