/// 仓库基类，提供通用结果包装
sealed class RepoResult<T> {
  const RepoResult();
  R when<R>({required R Function(T data) success, required R Function(String msg) failure}) =>
      switch (this) {
        RepoSuccess<T>() => success((this as RepoSuccess<T>).data),
        RepoFailure<T>() => failure((this as RepoFailure<T>).message),
      };
}

class RepoSuccess<T> extends RepoResult<T> {
  final T data;
  const RepoSuccess(this.data);
}

class RepoFailure<T> extends RepoResult<T> {
  final String message;
  const RepoFailure(this.message);
}

abstract class BaseRepository {
  RepoResult<T> ok<T>(T data) => RepoSuccess(data);
  RepoResult<T> fail<T>(String msg) => RepoFailure(msg);
}
