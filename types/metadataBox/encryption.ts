


export interface EncryptionResultType {
    encryption_data: string;
    encryption_iv: string;
}

export interface EncryptionDataType {
    encryption_slices_metadata_cid: EncryptionResultType;
    encryption_file_cid: EncryptionResultType[];
    encryption_passwords: EncryptionResultType;
    public_key: string,
    // privateKey: string,
}

// Key pair structure
export interface KeyPairType_Mint {
    private_key_minter: string;
    public_key_minter: string;
}