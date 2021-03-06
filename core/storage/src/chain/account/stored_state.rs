use models::node::{Account, AccountId};

#[derive(Debug, PartialEq)]
pub struct StoredAccountState {
    pub committed: Option<(AccountId, Account)>,
    pub verified: Option<(AccountId, Account)>,
}
