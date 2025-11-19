
export interface EncryptionFileCIDType {
    fileCID_encryption: string;
    fileCID_iv: string;
}

export interface EncryptionPasswordType {
    password_encryption: string;
    password_iv: string;
}

export interface EncryptionSlicesMetadataCIDType {
    slicesMetadataCID_encryption: string;
    slicesMetadataCID_iv: string;
}

export interface EncryptionDataType {
    encryptionSlicesMetadataCID: EncryptionSlicesMetadataCIDType;
    encryptionFileCID: EncryptionFileCIDType[];
    encryptionPasswords: EncryptionPasswordType;
    publicKey: string,
}
