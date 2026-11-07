const accountPasswordMinLength = 8;
const accountPasswordMaxLength = 64;

String? validateAccountPassword(String password) {
  if (password.length < accountPasswordMinLength ||
      password.length > accountPasswordMaxLength) {
    return '密码长度需为 8–64 位';
  }
  return null;
}
