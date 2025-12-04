table 72103 "WP QR Code Temp Blob"
{
    Caption = 'WP QR Code Temp Blob';
    DataClassification = ToBeClassified;
    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            DataClassification = CustomerContent;
            AutoIncrement = false;
            Editable = true;
        }

        field(2; "Text 1"; Text[250])
        {
            Caption = 'Text 1';
            DataClassification = CustomerContent;
            Editable = true;
        }
        field(3; "Text 2"; Text[250])
        {
            Caption = 'Text 2';
            DataClassification = CustomerContent;
            Editable = true;
        }
        field(4; "Text 3"; Text[250])
        {
            Caption = 'Text 3';
            DataClassification = CustomerContent;
            Editable = true;
        }
        field(5; "Text 4"; Text[250])
        {
            Caption = 'Text 4';
            DataClassification = CustomerContent;
            Editable = true;
        }
        field(6; "Text 5"; Text[250])
        {
            Caption = 'Text 5';
            DataClassification = CustomerContent;
            Editable = true;
        }
        field(7; "QR Code"; Blob)
        {
            Caption = 'QR Code';
            DataClassification = CustomerContent;
        }

    }

}
