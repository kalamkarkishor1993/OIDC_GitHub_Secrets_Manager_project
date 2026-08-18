data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "TerraformGitHubRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
                  "token.actions.githubusercontent.com:sub" = "repo:kalamkarkishor1993@*/OIDC_GitHub_Secrets_Manager_project@*:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_permissions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_iam_role_policy" "manage_own_role" {
  name = "allow-manage-own-role"
  role = aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies"
      ]
      Resource = aws_iam_role.github_actions.arn
    }]
  })
}

resource "aws_iam_role_policy" "read_oidc_provider" {
  name = "allow-read-oidc-provider"
  role = aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
      Resource = "*"
    }]
  })
}