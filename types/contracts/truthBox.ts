
// enum Status {Storing, Selling, Auctioning, Paid, Refunding, Delaying, Published, Blacklisted}
export const boxStatus = [
    'Storing',
    'Selling',
    'Auctioning',
    'Paid',
    'Refunding',
    'Delaying', // InSecrecy
    'Published',
    'Blacklisted',
] as const;

export type BoxStatus = typeof boxStatus[number];

