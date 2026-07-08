tableextension 70010 VNPAYStoreCard extends "LSC Store"
{
    fields
    {
        field(72107; "Enable VNPay Integration"; Boolean)
        {
            Caption = 'Enable VNPay Integration';
            DataClassification = ToBeClassified;
        }
        field(72108; "VNPAY Payment Service URL"; Text[70])
        {
            Caption = 'VNPAY Payment Service URL';
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
        field(72120; "Enable VCB Integration"; Boolean)
        {
            Caption = 'Enable VCB Integration';
            DataClassification = ToBeClassified;
        }
        field(72121; "VCB Payment Service URL"; Text[250])
        {
            Caption = 'VCB Payment Service URL';
            DataClassification = ToBeClassified;
        }
        field(72122; "VCB Terminal ID"; Text[20])
        {
            Caption = 'VCB Terminal ID';
            DataClassification = ToBeClassified;
        }
        field(72123; "VCB Merchant ID"; Text[20])
        {
            Caption = 'VCB Merchant ID';
            DataClassification = ToBeClassified;
        }
        field(72124; "VCB First Check Delay Sec"; Integer)
        {
            Caption = 'VCB First Check Delay Sec';
            DataClassification = ToBeClassified;
        }
        field(72125; "VCB Check Interval Sec"; Integer)
        {
            Caption = 'VCB Check Interval Sec';
            DataClassification = ToBeClassified;
        }
        field(72126; "VCB Max Retries"; Integer)
        {
            Caption = 'VCB Max Retries';
            DataClassification = ToBeClassified;
        }
        field(72127; "VCB Tender Type Code"; Code[10])
        {
            Caption = 'VCB Tender Type Code';
            DataClassification = ToBeClassified;
        }

    }
}
