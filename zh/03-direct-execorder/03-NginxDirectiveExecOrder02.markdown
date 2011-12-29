# Nginx 配置指令的执行顺序（二） #

我们前面已经知道，当 L<ngx_rewrite/set> 指令用在 C<location>
配置块中时，都是在当前请求的 C<rewrite> 阶段运行的。事实上，在此上下
文中，L<ngx_rewrite> 模块中的几乎
全部指令，都运行在 C<rewrite>
阶段，包括 L<vartut/Nginx 变量漫谈（二）> 中介绍过的 L<ngx_rewrite/rewrite>
指令。不过，值得一提的是，当这些指令使用在 C<server> 配置块中时，则会
运行在一个我们
尚未提及的更早的处理阶段，C<server rewrite> 阶段。

L<vartut/Nginx 变量漫谈（二）> 中介绍过的 L<ngx_set_misc>
模块的 L<ngx_set_misc/set_unescape_uri> 指令同
样也运行在 C<rewrite> 阶段。特别地，L<ngx_set_misc>
模块的指令还可以和 L<ngx_rewrite> 的指令混合在一起依次执行。我们
来看这样的一个例子：

    :nginx
    location /test {
        set $a "hello%20world";
        set_unescape_uri $b $a;
        set $c "$b!";

        echo $c;
    }

访问这个接口可以得到：

    :bash
    $ curl 'http://localhost:8080/test'
    hello world!

我们看到，L<ngx_set_misc/set_unescape_uri> 语句
前后的 L<ngx_rewrite/set> 语句都按书写时的顺序一前一后地执行
了。

为了进一步确认这一点，我们不妨再检查一下 Nginx 的“调试日志”（如果你
还不清楚如何开启“调试日志”的话，可以参考 L<ordertut/（一）> 中的
步骤）：

    :bash
    grep -E 'http script (value|copy|set)' t/servroot/logs/error.log

过滤出来的调试日志信息如下所示：

    :text
    [debug] 11167#0: *1 http script value: "hello%20world"
    [debug] 11167#0: *1 http script set $a
    [debug] 11167#0: *1 http script value (post filter): "hello world"
    [debug] 11167#0: *1 http script set $b
    [debug] 11167#0: *1 http script copy: "!"
    [debug] 11167#0: *1 http script set $c

开头的两行信息

    :text
    [debug] 11167#0: *1 http script value: "hello%20world"
    [debug] 11167#0: *1 http script set $a

就对应我们的配置语句

    :nginx
    set $a "hello%20world";

而接下来的两行

    :text
    [debug] 11167#0: *1 http script value (post filter): "hello world"
    [debug] 11167#0: *1 http script set $b

则对应配置语句

    :nginx
    set_unescape_uri $b $a;

我们看到第一行信息与 L<ngx_rewrite/set> 指令略有区别，多了
C<(output filter)> 这个标记，而且最后显示出 URI 解码操作
确实如我们期望的那样工作了，即 C<"hello%20world"> 在这里被成
功解码为 C<"hello world">.

而最后两行调试信息

    :text
    [debug] 11167#0: *1 http script copy: "!"
    [debug] 11167#0: *1 http script set $c

则对应最后一条 L<ngx_rewrite/set> 语句：

    :nginx
    set $c "$b!";

注意，因为这条指令在为 C<$c> 变量赋值时使用了“变量插值”功能，所以
第一行调试信息是以 C<http script copy> 起始的，后面则是拼
接到最终取值的字符串常量 C<"!">.

把这些调试信息联系起来看，我们不难发现，这些配置指令的实际执行顺序是：

    :nginx
    set $a "hello%20world";
    set_unescape_uri $b $a;
    set $c "$b!";

这与它们在配置文件中的书写顺序完全一致。

我们在 L<vartut/Nginx 变量漫谈（七）> 中初识了第三方模块 L<ngx_lua>，
它提供的 L<ngx_lua/set_by_lua> 配置指令也和 L<ngx_set_misc>
模块的指令一样，可以和 L<ngx_rewrite> 模块的指令混合使用。L<ngx_lua/set_by_lua>
指令支持通过一小段用户 Lua 代码来计算出一个结果，然后赋给指定的 Nginx
变量。和 L<ngx_rewrite/set> 指令相似，L<ngx_lua/set_by_lua>
指令也有自动创建不存在的 Nginx 变量的功能。

下面我们就来看一个 L<ngx_lua/set_by_lua> 指令与 L<ngx_rewrite/set>
指令混合使用的例子：

    :nginx
    location /test {
        set $a 32;
        set $b 56;
        set_by_lua $c "return ngx.var.a + ngx.var.b";
        set $equation "$a + $b = $c";

        echo $equation;
    }

这里我们先将 C<$a> 和 C<$b> 变量分别初始化为 C<32> 和 C<56>，
然后利用 L<ngx_lua/set_by_lua> 指令内联一行我们自己指定的
Lua 代码，计算出 Nginx 变量 C<$a> 和 C<$b> 的“代数和
”（sum），并赋给变量 C<$c>，接着利用“变量插值”功能，把变量 C<$a>、
C<$b> 和 C<$c> 的值拼接成一个字符串形式的等式，赋予变量 C<$equation>，
最后再用 L<ngx_echo/echo> 指令输出 C<$equation>
的值。

这个例子值得注意的地方是：首先，我们在 Lua 代码中是通过 L<ngx_lua/ngx.var.VARIABLE>
接口来读取 Nginx 变量 C<$VARIABLE> 的；其次，因为 Nginx
变量的值只有字符串这一种类型，所以在 Lua 代码里读取 C<ngx.var.a>
和 C<ngx.var.b> 时得到的其实都是 Lua 字符串类型的值 C<"32">
和 C<"56">；接着，我们对两
个字符串作加法运算会触发
Lua 对加数进行自动类型转换（Lua 会把两个加数先转换为数值类型再求和）；然
后，我们在 Lua
代码中把最终结果通过 C<return> 语句返回给外面的 Nginx
变量 C<$c>；最后，L<ngx_lua> 模块在给 C<$c> 实际赋值之前
，也会把 C<return> 语句返回的数值类型的结果，也就是 Lua 加法计算
得出的“和”，自动转换为字符串（这同样是因为 Nginx 变量的值只能是字符串）。

这个例子的实际运行结果符合我们的期望：

    :bash
    $ curl 'http://localhost:8080/test'
    32 + 56 = 88

于是这验证了 L<ngx_lua/set_by_lua> 指令确实也可以和 L<ngx_rewrite/set>
这样的 L<ngx_rewrite> 模块提供的指令混合在一起工作。

还有不少第三方模块，例如 L<vartut/Nginx 变量漫谈（八）>
中介绍过的 L<ngx_array_var> 以及后面即将接触到的用于加解密
用户会话（session）的 L<ngx_encrypted_session>，
也都可以和 L<ngx_rewrite> 模块的指令无缝混合工作。

标准 L<ngx_rewrite> 模块的应用是如此广泛，所以能够和它的配置
指令混合使用的第三方模块是幸运的。事实上，上面提到的这些第三方模块都采用了特殊的
技术，将它们自己的配置指令“注入”到了 L<ngx_rewrite> 模块的指令
序
列中（它们都借
助了 Marcus Clyne 编写的第三方模块 L<ngx_devel_kit>）。
换句话说，更多常规的在 Nginx 的 C<rewrite> 阶段注册和运行指令
的第三方模块就没那么幸运了。这些“常规模块”的指令虽然也运行在 C<rewrite>
阶
段，但其配置指令和 L<ngx_rewrite> 模块（以及同一阶段内的其他模块
）都是分
开独立执行的。在运行时，不同模块的配置指令集之间的先后顺序一般是不确定的（严格来
说，
一般是由模块的加载顺序决定的，但也有例外的情况）。比如 C<A> 和 C<B>
两个模块都在 C<rewrite> 阶段运行指令，于是要么是 C<A> 模块的
所有指令全部执行完再执行 C<B> 模块的那些指令，要么就是反过来，把 C<B>
的指
令全部执行完，再去运行 C<A> 的指令。除非模块的文档中有明确的交待，
否则用户
一般不应编写依赖于此种不确定顺序的配置。

